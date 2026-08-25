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

## Done

### WR-059 — Always resurface Settings on the current workspace

- **Type:** Settings window behavior change
- **Priority:** P2
- **Status:** Done
- **Requested outcome:** Every Settings command must bring the one existing Settings window to the
  front on the current WindowRanger workspace and interaction display, even when that window was
  already visible elsewhere.
- **Diagnostic-backed follow-up:** The first installed candidate could activate Settings from the
  status-menu action before AppKit finished that menu-tracking transaction. Diagnostics showed no
  Carbon hot-key deliveries during the resulting dead interval; unified logging then reported a
  stale deferred activation immediately before focusing another app released the state and the next
  shortcut dispatched normally. A follow-up candidate incorrectly treated delegate `menuDidClose`
  as the later tracking-end signal; live diagnostics showed that callback preceded the selected-item
  action, leaving `status-menu-open-deferred` pending, Settings unopened, and hotkeys unresponsive.
  The next candidate used `didEndTrackingNotification`, but the fresh installed trace proved popup
  tracking had also ended before the selected-item action; that request likewise remained pending.
  The post-action-notification candidate opened Settings, but the status-item hover remained frozen,
  Settings was visible without becoming key, and shortcuts stayed unavailable until Settings was
  clicked. The fresh trace then recorded the very next shortcut through the normal Carbon route.
  This proves `didSendActionNotification` was also delivered inside `NSMenu.popUp`'s nested event
  loop, before the synchronous popup presentation returned. The popup-return candidate then logged
  `status-menu-presentation-ended`, opened and surfaced Settings, but reproduced the same frozen
  status-item highlight and absent shortcut deliveries until another click. Carbon resumed unchanged
  afterward. The fault is therefore upstream of Settings and hot-key dispatch: the macOS 27 status
  button was configured to invoke detached menu presentation on mouse-down, allowing the menu's
  tracking loop to consume the matching mouse-up before the originating control completed. After
  that input fix, the next trace showed a separate retained-window lifecycle gap: following a normal
  Settings close, generation 3 requested a scene and generation 4 was coalesced, but neither could
  surface the already reopened SwiftUI window until an unrelated workspace update caused its reader
  to attach roughly ten seconds later.
- **Acceptance:** Reopening reassigns the existing utility without creating a duplicate, activates
  WindowRanger, moves the window to the requested display, and presents it key and frontmost on the
  active native macOS Space. A status-menu request waits for its popup presentation to return
  before activation, and global hotkeys remain responsive immediately afterward. Passive restoration during an
  ordinary workspace switch remains nonactivating. Focused Settings tests and the complete
  non-hosted suite pass; a signed build must be checked by opening Settings, using workspace and
  Quick App shortcuts immediately, switching workspace/Space, and opening Settings again.
- **Implemented:** Explicit opens retain the current virtual-workspace/display capture and floating
  utility lifecycle. An already-visible native window now clears any `canJoinAllSpaces` behavior,
  orders out before application activation so `moveToActiveSpace` is reapplied, then becomes key and
  frontmost. Standard display-group status buttons now dispatch only on mouse-up, and every detached
  menu request is coalesced and deferred one main-loop turn so its originating control action returns
  before popup tracking begins. The status-menu action then records one pending request; only after the synchronous
  `NSMenu.popUp` presentation returns does the controller consume it and perform the native Settings
  command on the following main-loop turn. It uses no close, tracking-end, or post-action notification
  as that boundary and does not call `cancelTracking()`; invalidation cancels the pending request.
  A normal close now retains the existing weakly backed Settings surface instead of immediately
  detaching it, allowing the next command to reopen and raise SwiftUI's retained `NSWindow` directly.
  If that window has actually been released, its unavailable adapter is discarded before the normal
  scene-opening path runs.
  Carbon remains the sole global shortcut path. Debug diagnostics now record menu request, control
  event completion, popup start and popup return in addition to the Settings handoff, window
  visibility, native Space reset, and virtual-workspace reassignment.
- **Automated evidence:** Test isolation, all 128 focused Radial Menu and Settings tests, and the
  complete 602-test non-hosted suite pass. Coverage proves a normally closed retained surface
  reopens directly without requesting another scene, while an actually released surface is
  discarded and requests a new scene. The earlier 171 focused Menu Bar, Radial Menu, and Settings
  tests also pass for the control-event boundary.
- **Installed evidence:** With explicit approval, signed universal Debug build
  `7d2284134f1e-dirty` (CDHash `df32cedbecbc21f56cc8aaea3a6d23130f760bba`) is installed and
  running as process `46165` from `/Applications/WindowRanger.app`. Its embedded revision, Apple
  Development signature, Team ID `44NAD22AK6`, bundle identity, `x86_64` and `arm64` architectures,
  and running executable path were verified. Fresh startup session
  `973903CD-0318-4C92-8F1A-7A4778A6A129` confirms the replacement launched normally. The rejected
  popup-return candidate's session `61FFD4FA-CC75-4736-B2C8-48934C4AF1FE` captured its completed
  Settings handoff followed by the same frozen input interval; normal Carbon delivery resumed after
  another app received focus. The earlier rejected
  `didEndTrackingNotification` candidate recorded
  `status-menu-open-deferred` but no tracking-ended or Settings-open event and twice failed the
  installer's graceful-quit timeout after becoming wedged, so only its exact installed process was
  terminated before replacement.
- **Live evidence:** On 20 August 2026, the maintainer confirmed the status-menu input fix restored
  shortcut responsiveness, then accepted the installed retained-window candidate after checking
  that an already-open Settings window returns to the front.

### WR-060 — Searchable command surface

- **Type:** Feature
- **Priority:** P2
- **Status:** Done
- **Source:** `docs/omarchy-inspired-ideas.md`
- **Requested outcome:** Replace the broad Command Wheel with a standard keyboard-first Command
  Palette on its existing configurable global shortcut. Keep an icon-only control beside search
  that expands Loop-style window positions around itself without closing the palette, and retain
  the optional Globe/Fn hold as a direct path to those same position choices.
- **Acceptance:** The palette shows only valid current window, workspace, layout, profile, and
  application commands; searches titles and useful synonyms; displays known shortcuts; supports
  arrow selection, Return, Escape, mouse selection, and shortcut-toggle dismissal; and never loses
  or retargets the external window merely because its search field became key. A command restores
  the prior application and revalidates the captured session before dispatch. The Placement Halo
  and Globe/Fn wheel expose only truthful Freeform or Tiled positions in stable compass order;
  the placement entry is omitted when none exist, arrows traverse available positions, Return
  commits, and Escape restores palette search. Layout, Accordion resize, and all other actions
  remain searchable. WR-065 owns the current compact Quick Actions entry and keyboard path. Existing
  shortcut persistence and legacy wheel preferences remain migration-safe. Focused tests, the
  complete non-hosted suite, an unsigned app build, and signed live use with real windows are
  required.
- **Implemented:** Added a searchable key panel backed by the established contextual catalogue,
  configurable shortcut registry, and shared typed dispatcher. The existing Control-Option-Space
  default now toggles the palette. It captures the external focus/workspace/display/profile token
  before activation, restores the previous application before selection, and rejects stale actions.
  The old renderer is retained as a one-level, position-only Placement Wheel for optional Globe/Fn
  hold. The original icon-only search-field control expanded a Placement Halo while keeping the key
  palette and its query alive; WR-065 later superseded that entry surface with a conditional stacked
  Quick Action. Settings no longer exposes the obsolete broad-wheel activation style or catalogue
  editor; legacy values remain decodable.
- **Current-state update:** WR-066 removes the superseded standalone Globe/Fn trigger and Placement
  Wheel settings/runtime wiring. Window placement remains available through the palette's inline
  Placement Halo; the old saved values stay decodable for compatibility.
- **Automated evidence:** Test isolation, six focused Command Palette tests, the owned-focus-anchor
  regression, the production Placement Halo offscreen render, and all 610 non-hosted tests pass.
  Coverage includes contextual/global command composition, stable grouped search order,
  unavailable-target filtering, shortcuts, profiles, layouts, position-only stable compass order,
  and direct Globe/Fn wheel resolution. The final unsigned Debug app build also succeeds. Visual QA
  against the selected option 1 reference has no unresolved P0/P1/P2 mismatch.
- **Installed evidence:** With explicit maintainer approval, signed universal Debug candidate
  `9ae89932e6bb-dirty`, including the selected inline position-only Placement Halo, is installed and
  running from `/Applications/WindowRanger.app` as process `58323`.
  Its strict code signature, Apple Development authority, Team ID `44NAD22AK6`, bundle
  identifier, embedded revision, `arm64` and `x86_64` architectures, running executable path, and
  CDHash `ed85175e9b39c1273981f6c1c830a282f37d151f` were verified. Fresh diagnostic session
  `CE3837A6-FAEB-42C5-A5AC-5447AD645237` started normally. The previous daily build remains at the
  repository-defined non-launchable rollback path.
- **Live defect found:** The first installed palette correctly captured managed window
  `22127:19779`, but its own key-panel activation was then consumed as an external focus change.
  Diagnostics showed the palette open with `focused-managed-window`, WindowRanger window
  `69767:20689` replace the interaction anchor 49 milliseconds later, and the palette dismiss as
  `context-changed`; subsequent opens consequently had no focused window and the Spatial Wheel had
  no relevant actions. Preserve the external managed anchor while any WindowRanger-owned or ignored
  utility surface has focus. A focused policy regression test covers owned, ignored, external, and
  absent focus observations.
- **Second live defect found:** The owned-focus correction kept the palette stable, but the active
  tiled workspace had one layout participant. Tiled placement therefore truthfully produced no
  previews, leaving the icon-only wheel button disabled with no diagnostic event. A labelled button
  and always-valid Layout Type fallback made the control discoverable but felt unnatural in live
  use. The selected correction is an icon-only, inline Placement Halo with no layout or resize
  fallback; when a window has no truthful position, those commands remain available through search.
- **Third live defect found:** The first installed halo made AppKit calculate its normal window
  shadow around the enlarged transparent panel, producing a strange black outline. The unavailable
  control also remained visible but disabled, and the halo had no palette-keyboard path. The current
  candidate disables the panel shadow only while expanded, omits the control when no placements
  exist, and adds Right Arrow entry, circular arrow navigation, Return commit, and Escape back to
  search.
- **Live evidence:** On 20 August 2026, the maintainer accepted the signed installed palette and
  inline Placement Halo after the external-focus correction, icon-only redesign, conditional
  availability, shadow correction, and full keyboard navigation were installed together. The
  accepted flow keeps the palette open while the halo expands and returns Escape focus to search.

## Inbox

### WR-086 — Make Shortcut Guide contextual while Quick App Shelf is open

- **Type:** Shortcut Guide and Quick App Shelf integration
- **Priority:** P2
- **Status:** Live validation — implemented, automated-test verified, visually checked, and installed;
  signed interaction acceptance pending.
- **Requested:** 25 August 2026.
- **User-observed context:** The normal Shortcut Guide can remain visible while the Shelf is open,
  but its generic window labels and full directional/action set do not describe what those keys do
  to Shelf-owned windows.
- **Smallest useful outcome:** Present a compact Shelf-specific Navigate guide on the Shelf display,
  positioned at the opposite screen edge. Keep valid workspace switching and Commands, label the
  toggle as Hide Shelf, name Previous/Next Shelf Window explicitly, and show only the Shelf layout
  axis. Suppress Arrange because those focused-window operations do not act on Shelf-owned windows.
- **Acceptance:** Opening or closing the Shelf while Navigate is held refreshes the visible guide
  without requiring a modifier release. Top/Bottom Shelves expose Left/Right focus; Left/Right
  Shelves expose Up/Down. The guide remains conflict-checked, passive, display-correct, adaptive for
  dense workspace bindings, and leaves Focus Border behavior unchanged. Focused policy/grouping
  tests, repository quick verification, a signed daily install, and live modifier-held use with an
  open multi-window Shelf are required.
- **Automated evidence:** All 19 focused Shortcut Guide tests pass, including Shelf filtering,
  relabeling, axis choice, compact density, opposite-edge placement, and Arrange suppression. Test
  isolation and repository quick verification pass all 728 non-hosted tests with zero failures.
- **Visual evidence:** All six Small/Medium/Large Light/Dark Shelf-context production-view renders
  were generated. Small Dark and Medium Light were inspected at original Retina resolution; the
  compact labels, two-line traversal actions, headings, arrow axis, spacing, and semantic contrast
  have no unresolved P0-P2 issue. `design-qa.md` records the boundary and evidence.
- **Installed evidence:** With maintainer approval, signed universal Debug daily candidate
  `3c263a750f0f` (CDHash `b0f4401b3f794808f9a65b28b5d0b4e6a5713653`) is installed and
  running from `/Applications/WindowRanger.app` as PID `65306`. Its strict signature, Apple
  Development authority, Team ID `44NAD22AK6`, canonical bundle identity, embedded source marker,
  `x86_64` and `arm64` architectures, running path, and exact built/installed executable and Debug
  dylib hashes were verified. Startup session `6C9748D5-9F71-43BB-A673-1CCDB9E1C5B0` reached
  `startup-state-ready` and prepared Notes as a one-window group and Ghostty as a two-window group.
  The previous daily remains recoverable at `/Applications/.WindowRanger.previous`.
- **Live validation needed:** With a multi-window Ghostty Shelf open, hold Navigate and confirm the
  compact guide appears opposite the Shelf, says Quick App Shelf, Hide Shelf, Previous/Next Shelf
  Window, and Focus Shelf Window, shows only the usable arrow axis, remains click-through, and
  dismisses on release. While continuing to hold Navigate, toggle the Shelf and confirm the guide
  changes context immediately. Hold Arrange while the Shelf is open and confirm no misleading guide
  appears. Confirm the Focus Border remains on the selected Shelf window without visual conflict.

### WR-085 — Treat each Quick App as an all-window Shelf group

- **Type:** Quick App Shelf ownership and interaction change
- **Priority:** P1
- **Status:** Neighbour window-ordering fix implemented and automated-verified; signed retest pending.
- **Requested:** 25 August 2026.
- **User decision:** The Shelf is a temporary workspace containing the eligible windows of its
  configured applications, not a launcher containing one representative window per application.
- **Smallest useful outcome:** A configured Shelf application with multiple admitted standard
  windows owns, presents, lays out, focuses, hides, restores, and persists every one of those exact
  windows. The existing visible-count setting continues to bound configured applications; all
  eligible windows belonging to each visible application participate in Carousel or Accordion.
- **Safety boundary:** Application Hide remains one application-level transition. Ignored/transient
  surfaces, deferred windows, full-screen windows, and windows from another process remain excluded;
  admitted dialog and fixed-size safety still preserve their position-only geometry boundary.
  Newly admitted same-process windows join the existing application group; removal releases only
  that exact window unless the group becomes empty. Every owned window keeps its prior workspace,
  frame, layout order, and restore state. Legacy one-window persisted sessions continue to decode.
- **Interaction boundary:** Directional focus and Previous/Next Window can select each visible Shelf
  window without relaying out the group merely to change focus. Application selection and the
  configured application order remain stable, while diagnostics distinguish visible applications
  from visible windows.
- **Acceptance:** Startup and an ordinary direct toggle claim two genuine same-process Ghostty
  windows without ambiguity feedback; both windows receive deterministic Carousel and Accordion
  frames, remain outside normal workspace layout while owned, follow application-wide hide/show,
  and restore safely when Shelf ownership ends. Adding and closing a Ghostty window updates only
  that application group. Multi-process ambiguity still fails closed. Focused policy, geometry,
  persistence, navigation, lifecycle, and full non-hosted verification pass before signed live
  validation.
- **Implemented:** Shelf sessions now retain a deterministic exact-window group per application.
  Startup, direct selection, launched-window discovery, visible neighbours, refresh admission,
  removal, ignored-surface eviction, native-tab replacement, persistence, wake recovery, hide/show,
  configuration cleanup, and restoration operate on that group. Carousel and Accordion flatten all
  windows from the visible configured applications; the visible-count setting still counts apps.
  Directional focus targets every presented window, while Previous/Next traverses the stable window
  order before moving to the next configured app. Hidden applications are staged into their final
  Shelf frames before Unhide, and a presented app's newly admitted window triggers immediate group
  layout. The superseded WR-084 one-window startup recovery has been removed.
- **Automated evidence:** 60 focused Quick App tests pass, covering same-process grouping,
  cross-process rejection, stable cycling, exact-member removal, one-for-one native-tab handoff with
  retained group members, legacy persistence, and seven-window Carousel/Accordion geometry at all
  four edges. The live-settings propagation and visible-window stacking regression tests, plus all
  30 tests in `QuickAppShelfTests`, pass. The complete non-hosted suite passes 730 tests with zero
  failures or skips. Test isolation, shell syntax, release-build registry, Sparkle feed workflow,
  project generation,
  Release static analysis, unsigned universal Release build, and Stable/Beta DMG build and
  verification all pass (25 August 2026).
- **Live validation remaining:** Repeat the two-window Ghostty case across direct toggle and
  restart. Then check both layouts, app-wide hide/show, Previous/Next
  and arrow navigation, adding and closing one Ghostty window while presented, and final restoration
  to the original workspaces and frames.
- **Live defect found:** The maintainer confirmed both Ghostty windows appeared, but the Shelf kept
  using Accordion and appeared to show only one configured application even though the active
  profile saved Carousel with a visible-app count of two and both Notes and Ghostty were open.
  Diagnostics from installed candidate `51c9fb776f29` confirmed the running engine continued to
  report `style=accordion`; it later admitted all three windows from both applications, so the
  saved profile and multi-application admission were intact. Active Settings profile edits were
  incorrectly marked as profile activation while publishing, causing AppDelegate's live-engine
  subscriptions to discard them. The fix now separates Settings profile-content replacement from
  genuine profile activation, preserving bulk persistence guards while allowing live engine
  subscribers to receive active-profile edits.
- **Second live defect found:** On the fixed candidate, the maintainer saw Notes alone on first
  presentation; navigating to the next Shelf window then revealed both Ghostty windows. Diagnostics
  confirmed Carousel and visible-app count two were active, and the engine laid out Notes plus both
  Ghostty windows at the correct group stage. The neighbour windows were unhidden and framed but
  not raised above ordinary desktop windows; navigation made Ghostty frontmost and exposed both.
  Group layout now raises every visible exact Shelf window after unhide confirmation, keeping the
  selected window last for deterministic focus and Accordion stacking while hidden neighbours
  remain staged without being raised.
- **Installed evidence:** With maintainer approval, signed Debug daily candidate
  `3c263a750f0f` is installed and running from `/Applications/WindowRanger.app` as PID `65306`.
  The built and installed executable and Debug dylib match exactly; strict signature validation,
  canonical bundle identity, Team ID `44NAD22AK6`, both `x86_64` and `arm64` architectures, running
  path, and CDHash `b0f4401b3f794808f9a65b28b5d0b4e6a5713653` were verified. Startup session
  `6C9748D5-9F71-43BB-A673-1CCDB9E1C5B0` prepared Notes as a one-window group and Ghostty as a
  two-window application group, then reached `session/startup-state-ready`. This candidate includes
  the live Settings propagation fix and WR-086's contextual Shortcut Guide. This is installed
  startup smoke evidence; the interaction cases above remain for maintainer validation. The
  previous daily copy remains recoverable at
  `/Applications/.WindowRanger.previous`.

### WR-084 — Reconcile transient startup Quick App window ambiguity once

- **Type:** Quick App post-login recovery bug
- **Priority:** P1
- **Status:** Superseded by WR-085; the one-window recovery path is no longer active.
- **Requested:** 25 August 2026.
- **User-observed and diagnostic-supported:** After the 24 August reboot, Ghostty and WindowRanger
  launched 15 seconds apart. The user reported multiple-window feedback on the first direct Quick
  App attempt. Diagnostics do not retain that feedback text, but show four shortcuts at 08:10 local
  time displaying feedback without selecting a target. Focusing Ghostty caused its next successful
  Accessibility snapshot to evict window identities `1442:116` and `1442:120`; 2.6 seconds later,
  the shortcut unambiguously presented `1442:125` at the expected frame.
- **Prior expected behavior:** Preserve the exact-window safety boundary for genuine multi-window applications,
  while handling applications that publish transient login-restoration Accessibility windows until
  their first activation. A direct shortcut may activate such an already-running application once,
  but must never guess a target or repeatedly steal focus.
- **Prior implementation (superseded):** Startup recorded only configured Quick Apps with more than one eligible candidate.
  Their first direct hotkey toggle, when the candidate PID and exact window identities still match
  that immutable startup fingerprint and the application remains inactive, consumes the marker,
  activates the existing process without a reopen request, and performs a bounded sequence of
  read-only window refreshes. The matching application-activation notification is also restricted
  to read-only, no-focus-observation reconciliation until the bounded recovery completes, so it
  cannot arrange or hide a transient candidate first. Exactly one surviving candidate continues
  through the ordinary Quick App claim and presentation path; zero or multiple candidates retain
  explicit feedback. Command
  Palette and shelf-selection commands, changed candidate sets, cross-process ambiguity, active
  applications, later ambiguity, configuration and profile changes, cancellation, pause, sleep, and
  shutdown do not gain a guessing path. The focus that preceded recovery is retained for the normal
  hide-and-restore interaction.
- **Prior automated evidence:** Test isolation passed; 37 focused Quick App tests and 22 Command Palette
  tests pass, including command-source propagation, the exact-startup-fingerprint boundary, one-shot
  activation, read-only activation reconciliation, exact-one resolution, and bounded retry
  exhaustion. The complete non-hosted suite passes with 729 tests and zero failures, together with
  project generation, release-ledger, Sparkle feed-ordering, and local quick-verification checks
  (25 August 2026).
- **Signed-build evidence:** The universal signed Debug daily copy `e0d7a5a259e2-dirty` was installed
  on 25 August 2026 with the previous copy retained for rollback. PID `21412` remained running after
  startup; signature validation passed, no fresh WindowRanger crash report or macOS error/fault was
  present, and diagnostics reached `session/startup-state-ready`. Ghostty window `1442:1339` was
  admitted normally and prepared as the single hidden Quick App. This is startup smoke evidence, not
  a reproduction of the post-reboot ambiguity or the recovery path. The user subsequently reported
  that the installed copy seemed to be working; the reboot-specific acceptance case remains pending.
- **Superseded acceptance:** Pure tests covered startup candidate counting, command-source and exact-fingerprint
  boundaries, the one-shot activation boundary, Command Palette/active/cross-process exclusions,
  exact-one resolution, bounded zero/multiple retries, and exhaustion. Focused Quick App tests and
  the complete non-hosted suite pass. Lifecycle/configuration invalidation is code-reviewed but is
  not claimed as live behavior until the signed-app test. A signed build is restarted with Ghostty
  restored at login; the first direct shortcut resolves without a manual focus step, while a genuine
  two-window Ghostty set still reports ambiguity after one bounded attempt and a later shortcut does
  not activate it again.
- **Live validation update (25 August 2026):** With both genuine Ghostty windows already present,
  restarting WindowRanger and invoking the direct shortcut reported the expected ambiguity. The
  maintainer then chose WR-085's all-window application-group model, which supersedes genuine
  same-process multi-window ambiguity as a desired final behavior. WR-085 removes the one-shot
  startup-ambiguity recovery and its tests; only cross-process ambiguity still fails closed.

### WR-083 — Decide the fate of historical whole-application and floating-panel exclusions

- **Type:** Product-policy recovery
- **Status:** Needs decision; research only, not approved for implementation.
- **Discovered:** 24 August 2026 while auditing all WindowRanger worktrees after the Beta 8 release.
- **Historical state:** The dirty, uncommitted worktree
  `/Users/chris/Developer/windowranger-wr046-stable-layout` predates current `develop`. Its retained
  layout-slot implementation is superseded by WR-081 and includes the unreadable-dialog retention
  bug corrected before Beta 8. Preserve it as historical WIP; do not merge that implementation.
- **Unique proposals still present there:** An Application Rule that leaves an entire application
  unmanaged, and a generic admission rule that ignores `AXFloatingWindow` and
  `AXSystemFloatingWindow`, were never incorporated. The current product instead uses narrow,
  evidence-backed admission and focused-window compatibility rules; a blanket exclusion could omit
  legitimate windows from management.
- **Decision boundary:** Decide independently whether a reversible whole-application unmanaged mode
  is desirable and whether any native floating-panel subrole can be ignored without corroborating
  metadata. If approved, redesign each proposal from current `develop` with new acceptance criteria,
  tests, and live validation. Do not revive the stale worktree patch or its reused WR identifiers.
- **Related stale worktree:** `/Users/chris/Developer/windowranger-wr042-game-input` is fully
  superseded by the committed WR-047 passive-observation/dedicated-filter design and has no code to
  recover. Neither historical worktree should be cleaned or removed without explicit maintainer
  direction.

### WR-079 — Keep DesktopRanger-owned surfaces outside WindowRanger

- **Type:** Window-admission compatibility and companion-app safety
- **Priority:** P1
- **Status:** Source implementation, complete automation, and one-display UTM coexistence pass;
  supported physical-Mac validation remains.
- **Requested:** 23 August 2026.
- **User-observed context:** DesktopRanger's persistent desktop, overlay, ordinary drawing, Recovery,
  and interaction-island surfaces can otherwise look like ordinary application windows to
  WindowRanger and enter workspace membership, layout, focus, or recovery state.
- **Smallest useful outcome:** Ignore only host-owned DesktopRanger surfaces carrying the exact
  Accessibility identifier `dev.appranger.desktopranger.surface.v1` from exact bundle identifier
  `dev.appranger.DesktopRanger.SurfaceLab`. Untagged SurfaceLab manager windows remain eligible for
  ordinary management. Do not invent or pre-admit a future production bundle identifier.
- **Ownership boundary:** DesktopRanger's Swift host owns the marker and plugins cannot create or
  retag native windows. WindowRanger treats the exact bundle-plus-marker pair as a local,
  versioned compatibility fact at central admission; it does not add a whole-application exclusion,
  trust arbitrary third-party markers, or expose arbitrary AX identifiers in diagnostics.
- **Acceptance:** The exact SurfaceLab bundle with the exact marker is ignored using a persistent
  companion-surface disposition across representative roles, subroles, and WindowServer layers.
  Missing markers, prefix/suffix/near matches, and the marker on another bundle stay conservatively
  admitted. A newly matching surface already in
  WindowRanger state is evicted from membership, pending restoration, layout, and focus history
  without an AX frame write. Any matching Quick App session is discarded, its application is made
  visible through a bounded confirmation path, and no recovery frame is written. An unconfirmed
  unhide retains visibility-only recovery debt with no window or geometry capability; a new Quick
  App session supersedes older retry generations. Exact PID-and-bundle debt survives a
  WindowRanger restart and receives an orderly-shutdown unhide attempt. A transient AX
  identifier failure never re-admits a previously confirmed surface and fails closed until a first
  classification can be completed. Focused admission, state-eviction, and Quick App tests plus the
  complete non-hosted suite pass. A
  supported physical installed check must repeat the UTM-confirmed AX export and stability through
  one WindowRanger workspace, layout, and focus cycle while an untagged DesktopRanger manager window
  remains manageable.
- **Current candidate evidence (24 August 2026):** After the explicit persistent-surface disposition,
  SurfaceLab-only identity correction, and late-marker transition coverage, 151 focused admission,
  eviction, and Quick App tests passed. `./scripts/verify-local-ci.sh --full` passed the complete
  isolated 698-test suite with no failures, static analysis, unsigned universal Release build, and
  Stable/Beta DMG smoke verification. In the macOS 26.6.2 build 25G83 UTM guest, the final diagnostic
  candidate classified exact tagged SurfaceLab Recovery/drawing windows as
  `ignored-companion-surface` while the unmarked normal manager probe from the same process remained
  `managed-normal`. Desktop/Floating/Bounded, click-through, interaction-island, Pause All, and the
  retained Ordinary close → Floating → Ordinary crash sequence passed visibly with both processes
  alive and no current SurfaceLab crash report. Four native focus cycles targeted exactly Terminal,
  Finder, System Settings, and the unmarked manager probe; tagged Recovery/drawing IDs never entered
  the layout targets. The guest lane proves the exact AX contract and visible one-display
  coexistence, not release signing, multi-display behaviour, or the supported physical-Mac matrix.
### WR-078 — Label Shortcut Guide actions by target

- **Type:** Shortcut discoverability improvement
- **Priority:** P2
- **Status:** Live validation — implemented, automated-test verified, native visual QA passed, and
  the installed refinement was accepted at the current density; supported-size sweep pending.
- **Requested:** 24 August 2026.
- **User-observed context:** The guide labels made it hard for newer users to distinguish workspace
  navigation from window navigation. “Previous” and “Next” did not say what would be cycled, while
  arrow actions duplicated the visual weight of ordered window cycling without explaining their
  spatial behavior. In the first installed labelled guide, the lower headings and actions were not
  consistently centred within their sections, and the Space keycap left too little room around its
  word.
- **Smallest useful outcome:** Keep the existing **Navigate** and **Arrange** family names, then group
  each visible command under a compact action-and-target heading. Centre “Focus by direction” or
  “Reorder by direction” beneath the arrow pad; identify workspace switching, ordered window cycling,
  focused-window arrangement, layout choice, and workspace display movement at a glance.
- **Acceptance:** Both families preserve the conflict-checked configured action set, arbitrary
  workspace keys, adaptive dense layouts, local size/position preferences, passive input/focus
  behavior, and native Light/Dark materials. Focused grouping/layout tests, production offscreen
  renders at supported densities, full non-hosted verification, and signed live modifier-held use
  are required.
- **Implemented:** Navigate and Arrange retain their existing family names and configured bindings.
  Workspace destinations and the centred spatial arrow pad form the top band; the lower band groups
  commands as Switch Workspace, Cycle Windows in Order, Arrange Window, Choose Layout, and Move
  Workspace. Small density shortens only the already-scoped Previous/Next/Last action labels beneath
  Switch Workspace, avoiding ellipses without losing the target. Lower group headings, action pairs,
  and rows are now centred within their allocated containers. The Space keycap has dedicated side
  padding and keeps its label at intrinsic width so the full word remains visible even at Small.
- **Automated evidence:** On 24 August 2026, all 16 focused Shortcut Guide tests passed, including
  exact group membership and labels. Repository quick verification then passed all 704 non-hosted
  tests, and the unsigned universal Debug app built successfully with arm64 and x86_64 slices.
- **Visual evidence:** All 12 native Small/Medium/Large Light/Dark Navigate and Arrange renders were
  inspected. The first Small pass exposed clipped workspace action labels and an undersized Arrange
  arrow-caption column; both were corrected. A later installed pass exposed inconsistent optical
  centring and an under-padded Space key, which were corrected and checked again across all 12
  renders. Matched full-view and focused lower-band comparisons have no remaining P0-P2 issue;
  `design-qa.md` records the evidence.
- **Installed evidence:** With explicit approval, refined signed universal Debug candidate
  `9f154f7a6a79-dirty` (CDHash `57ebd6606f3f676f83310258ae0ab9e54371edc6`) is installed and
  running from `/Applications/WindowRanger.app` as process `88912`. Its strict signature, Apple
  Development authority, Team ID `44NAD22AK6`, bundle identity, embedded source marker, arm64 and
  x86_64 slices, running executable path, and retained rollback copy were verified. Fresh session
  `043436B5-BA16-496B-920A-B8CB5C111770` started the passive modifier monitor and recorded both
  Navigate and Arrange presentation requests with `panel-visible=true`.
- **Live validation remaining:** Hold each configured modifier family at Small, Medium, and Large,
  and confirm the refined lower-group centring and wider Space keycap in the real Liquid Glass panel;
  also confirm it remains legible, passive, centred on the interaction display, and dismisses
  immediately on release. The user accepted the installed alignment at the current configured
  density on 24 August 2026.

### WR-077 — Hide every unambiguous Quick App Shelf entry at startup

- **Type:** Quick App Shelf startup bug
- **Priority:** P1
- **Status:** Live validation — implemented, automated-test verified, and signed restart evidence
  recorded; end-to-end Shelf presentation acceptance pending.
- **Requested:** 24 August 2026.
- **User-observed (2026-08-24):** On some WindowRanger starts, Quick Shelf applications remained
  visible instead of being hidden away.
- **Diagnostic evidence:** Startup session `6B1D889A-FE1C-4AD6-B621-DE1D2AF09407` claimed visible
  Ghostty window `917:14423` with `presented=true` and laid it out as a presented Shelf entry. No
  hide was attempted at startup; the application was hidden successfully only 66 seconds later
  after another application received focus. The startup policy was therefore deliberately retaining
  pre-launch visibility rather than encountering a failed Hide request. It also prepared only the
  selected Shelf entry, leaving other configured entries dependent on persisted ownership.
- **Expected:** Starting WindowRanger hides every configured Shelf application for which exactly one
  safe eligible window can be identified. Pre-launch visibility must not implicitly present a Shelf
  entry or let a nonselected entry join ordinary workspace layout. Externally hidden applications
  and ambiguous multiple-window sets remain untouched; exact persisted WindowRanger hide ownership
  remains recoverable.
- **Implemented:** Startup no longer derives presented state from a Shelf window's pre-launch
  visibility. It independently claims every configured Shelf entry with one safe eligible window,
  begins each session hidden, and requests application Hide before ordinary workspace layout. The
  existing exact persisted-ownership recovery, external-hide separation, deferred/full-screen
  exclusion, and multiple-window ambiguity boundary remain intact. Startup diagnostics now emit one
  preparation record per claimed entry and retain pre-launch visibility as evidence without using it
  to present the entry.
- **Acceptance:** Focused policy tests cover visible and legacy parked windows, exact persisted hide
  ownership, every independently selected Shelf entry, unrelated windows, and ambiguous matching
  windows. The complete non-hosted suite passes. A signed restart with at least two configured Shelf
  applications confirms both begin hidden and remain available through normal Shelf selection.
- **Automated evidence:** On 24 August 2026, all 51 focused DropDown App and Quick App Shelf tests
  passed, followed by test isolation, repository checks, and the complete 702-test non-hosted suite.
- **Installed evidence:** With explicit approval, signed universal Debug build
  `9f154f7a6a79-dirty` (CDHash `40b44bb4da1409e4cd4548b78b659bc6fc494271`) was installed and
  launched from `/Applications/WindowRanger.app`. Its Apple Development signature, Team ID
  `44NAD22AK6`, bundle identity, embedded source marker, two architectures, and running executable
  path were verified. Fresh startup session `79368B60-467E-4506-831F-9430A0629DB4` observed both
  Notes and Ghostty as visible before launch, then prepared each independently with `presented=false`
  and an accepted Hide request before ordinary layout.
- **Live validation remaining:** Confirm both entries are visually hidden after this restart and can
  still be presented normally from the Shelf.

### WR-075 — Exclude externally hidden applications from active layout geometry

- **Type:** Workspace visibility bug
- **Priority:** P1
- **Status:** Live validation — implemented and automated-test verified; signed installed-app checks
  remain.
- **Requested:** 24 August 2026.
- **User-observed (2026-08-24):** Workspace 2 visibly shifted from one full-width ChatGPT/Codex
  window to a two-window Accordion even though TextEdit was hidden and no second application window
  was visibly presented.
- **Diagnostic evidence:** Workspace 2 correctly solved one participant until TextEdit exposed
  window `49996:51782`. After TextEdit became hidden, AppKit reported the application itself as
  hidden while Accessibility continued to report its unminimized standard window at an on-screen
  frame. WindowRanger therefore treated that frame as meaningfully visible, retained two Accordion
  participants, and reduced ChatGPT/Codex by 250 points. Once TextEdit and its window closed, the
  successful Accessibility snapshot evicted that exact window and ChatGPT/Codex immediately returned
  to the complete `3832 x 1582` managed bounds.
- **Expected:** A genuinely windowless application contributes no participant, as it does today. An
  externally hidden application's enumerated windows remain tracked with their workspace and restore
  state intact, but do not participate in layout, focus candidates, or geometry writes until the
  application becomes visible again. Hidden state must trigger a background reflow without treating
  the application as terminated, moving its hidden windows, or weakening exact Quick App hide
  ownership.
- **Implemented:** Externally hidden ordinary applications remain tracked with their workspace and
  restore state, but are excluded from layout, focus, manual-move reconciliation, and every central
  geometry-write path. Application visibility is part of the background layout signature, so hide
  and unhide trigger full visibility reconciliation; an unhidden window assigned to an inactive
  workspace is parked normally. Quit recovery, wake focus recovery, and the final managed-focus
  boundary all reject hidden ordinary applications. Exact Quick App sessions retain their existing
  WindowRanger-owned hide behavior.
- **Acceptance:** Pure tests cover visible-to-hidden and hidden-to-visible transitions, retained
  assignment and restore geometry, immediate reflow, focus exclusion, inactive-workspace unhide,
  Quick App ownership, and application termination while hidden. Signed live validation hides and
  unhides a normal managed app without leaving an empty Accordion/Tiled slot or losing its workspace.
- **Automated evidence:** On 24 August 2026, 190 focused admission, geometry, diagnostics, and
  hidden-application policy tests passed, followed by the complete 700-test non-hosted suite and
  local project/release checks. Coverage includes visibility-signature reflow, wake-focus exclusion,
  Quick App separation, and the shared geometry exclusion used by quit recovery.
- **Installed evidence:** On 24 August 2026, the signed Debug daily candidate
  `cdd85908c712-dirty` was installed at `/Applications/WindowRanger.app`; its signature verified and
  the installed process launched from that exact bundle.
- **Live validation remaining:** Hide and unhide a normal app on active and inactive workspaces.
  Confirm no empty layout slot remains, the assignment survives, an inactive-workspace unhide does
  not surface the app, and Quick App hiding is unchanged.

### WR-076 — Keep native file-selection surfaces out of managed layouts

- **Type:** Window-admission bug
- **Priority:** P1
- **Status:** Live validation — revised signed Open-panel behavior accepted; ordinary document and
  Arrange-F checks remain.
- **Requested:** 24 August 2026.
- **User-observed (2026-08-24):** Focusing newly launched TextEdit produced its native file Open
  surface; WindowRanger expanded that surface to almost the full display and inserted it beside the
  existing ChatGPT/Codex window.
- **Diagnostic evidence:** TextEdit's Open surface presented as a layer-unknown `AXWindow` /
  `AXStandardWindow`, not minimized or fullscreen, with Close absent, Minimize and Zoom unavailable,
  modal state unsupported, and no authoritative move/resize capability evidence. The conservative
  normal-window fallback admitted it, and the successful frame write changed it from
  `369,83;3102 x 1380` to `254,34;3582 x 1582` as the second Accordion participant.
- **Expected:** A native file-selection surface floats at its application-chosen size and remains
  outside Tiled and Accordion layouts. Classification must use captured, non-textual Accessibility
  evidence rather than the localized title `Open`, dimensions, a TextEdit-specific exception, or a
  broad rule that floats ordinary document windows when capability reads are unavailable.
- **Installed validation failure (2026-08-24):** The first signed candidate still admitted the live
  TextEdit Open panel as `normal-window`. Fresh diagnostics proved both Default and Cancel
  relationships returned absent on this macOS build even though the window declared those
  attributes, so the fixture's affirmative relationships did not match the live surface.
- **Implemented:** A conservative, one-time Accessibility support probe recognizes only a closeless
  standard window that either affirmatively exposes both native Default and Cancel button
  relationships or carries AppKit's exact nonlocalized `open-panel`/`save-panel` Accessibility
  identifier. The raw identifier is reduced immediately to a privacy-safe boolean and is neither
  retained nor logged. That surface is admitted as a floating managed dialog and receives
  position-only safety writes, so it neither consumes a Tiled/Accordion slot nor gets resized.
  Missing, failed, unrelated, partial, or contradictory evidence falls back to ordinary admission;
  Arrange F cannot override this protected dialog classification. The rule uses no title, label,
  path, size, document value, application identity, or bundle-specific exception.
- **Acceptance:** Capture a deterministic fixture for this exact surface, establish the narrowest
  source-level admission evidence, and cover native Open/Save panels plus ordinary standard document
  windows with overlapping incomplete metadata. Signed live validation confirms the panel is neither
  resized nor counted while ordinary TextEdit documents remain managed.
- **Automated evidence:** After the installed mismatch, 171 focused tests and the complete 702-test
  non-hosted suite passed on 24 August 2026. Fixtures now reproduce the live Open panel's absent
  relationship values and affirmative native-panel identifier, plus Save-panel identifiers,
  unrelated identifiers, ordinary documents with overlapping controls, failed and partial reads,
  nonnormal layers, retained support evidence, position-only writes, protected Arrange-F feedback,
  privacy-safe diagnostics, and snapshot schema migration.
- **Installed evidence:** The signed Debug daily candidate `cdd85908c712-dirty` was installed and
  launched from `/Applications/WindowRanger.app` on 24 August 2026. After the first candidate's live
  mismatch, the identifier-based revision was rebuilt, signature-verified, installed, and launched
  from the same exact bundle.
- **Live evidence:** On 24 August 2026, the maintainer accepted the revised signed TextEdit Open-panel
  behavior after confirming it retained its native floating presentation instead of being controlled
  as a layout window.
- **Live validation remaining:** Confirm the same behavior for a native Save panel, an ordinary
  TextEdit document remains managed, and Arrange F reports the protected-dialog explanation.
### WR-071 — Switch profiles for foreground full-screen Game Mode sessions

- **Type:** Automatic profile selection
- **Priority:** P1
- **Status:** Automated implementation complete; signed-app and live-game validation remain.
- **Requested:** 23 August 2026.
- **User-observed context:** Games that activate macOS Game Mode need a purpose-built profile without
  requiring a manual profile change on launch and another change on exit.
- **Smallest useful outcome:** Let this Mac map one profile to a foreground full-screen game whose
  bundle explicitly declares `LSSupportsGameMode`. Manual profile pins remain authoritative; otherwise the
  Game Mode target takes priority over display and dock rules. Ending the session re-evaluates the
  ordinary automatic rules rather than restoring a stale remembered profile.
- **Detection boundary:** Public macOS APIs do not expose a direct, supported `isGameModeActive`
  property. WindowRanger therefore requires both an explicit `LSSupportsGameMode` declaration and
  a foreground full-screen window; a Games category or Game Controller declaration alone is not
  enough. The UI and documentation must not claim it can
  observe a user's per-game Game Mode override directly.
- **Acceptance:** The mapping is local to this Mac, survives profile edits safely, does not replace
  the profile being edited in Settings, switches through the normal generation-guarded profile
  transition, and returns to the currently resolved ordinary profile when the session ends.
- **Automated evidence:** On 23 August 2026, the isolated non-hosted suite passed 686 tests, including
  explicit `LSSupportsGameMode` eligibility, category/controller-only exclusion, local mapping,
  precedence, deletion, undo, and restart coverage. The unsigned arm64 Debug app also builds.

### WR-072 — Pause WindowRanger without losing the Command Palette escape hatch

- **Type:** Runtime control and safety
- **Priority:** P1
- **Status:** Automated implementation complete; signed-app and live-window validation remain.
- **Requested:** 23 August 2026.
- **Smallest useful outcome:** Add a transient Pause state, available from both the menu bar and
  Command Palette. While paused, retain only the Command Palette global shortcut; disable all other
  WindowRanger shortcuts, workspace swipes, shortcut-guide observation, and automatic window writes.
  WindowRanger must ignore manual moves and resizes rather than learning them. Resuming performs one
  fresh reconciliation so managed layouts snap windows back only where the active workspace rules
  require it.
- **Ownership boundary:** Pause is runtime-only and resets off at launch. It must not mutate profile
  content, window membership, saved layout intent, or iCloud/local Settings state merely by being
  toggled.
- **Acceptance:** Menu bar and palette can pause and resume; the palette shortcut remains usable
  while paused even if its normal assignment was disabled; stale registrations and queued Shelf
  transitions cannot dispatch other commands or window actions; windows remain freely movable
  and resizable without corrective writes until resume; resume respects the current profile,
  workspace layout, full-screen-game shortcut scope, and any independently active suppression reason.
- **Automated evidence:** On 23 August 2026, test isolation passed and all 686 non-hosted tests passed,
  covering the pause-only palette catalogue, forced family-aware escape shortcut, command routing,
  and runtime/local-state boundaries. The unsigned arm64 Debug app builds; signed live window,
  Shelf, display-change, Game Mode, and resume reconciliation checks remain.

### WR-074 — Define the DesktopRanger integration and structured CLI contract

- **Type:** Integration contract and CLI research
- **Priority:** P2
- **Status:** Needs decision; product direction is approved, but the public contract is not scoped or
  implemented.
- **Source:** `docs/desktop-ranger-integration.md`
- **Requested outcome:** Define a deliberately small, versioned, non-interactive WindowRanger command
  contract that lets the DesktopRanger host expose bounded typed operations without giving plugins
  shell access, private state, or a second workspace engine.
- **Acceptance:** Choose the initial query/control allowlist, request/response/error envelopes,
  privacy grants, compatibility and migration policy, same-user authenticated IPC, designated-signing
  checks, deadlines, cancellation, idempotency, and relaunch/concurrency semantics. Converge every
  exposed UI and CLI operation on the same validation and engine path. Test missing or incompatible
  peers, malformed and oversized messages, wrong signer/path substitution, stale or duplicate
  operations, timeouts, cancellation, late replies, and owner relaunch. Keep the integration
  unavailable or simulated until signed two-app validation passes without weakening macOS protections
  or changing the Apple Dock.

### WR-070 — Add a branded, settings-backed first-run onboarding wizard

- **Type:** First-run experience and feature education
- **Priority:** P1
- **Status:** Live validation — the signed daily walkthrough, repeat-setup Settings route, and
  corrected mouse controls have maintainer interaction evidence. The remaining first-run,
  permission, keyboard, picker, resume, and completion boundaries are listed below.
- **Requested:** 22 August 2026.
- **User-observed context:** WindowRanger now has a coherent core model, but a new user must discover
  iCloud, Navigate/Arrange shortcut families, Focus Border, menu-bar presentation, the Quick App
  Shelf, and workspace navigation independently in Settings. There is no first-run walkthrough.
- **Smallest useful outcome:** Present a resumable seven-stage native wizard on first launch:
  Welcome, iCloud, Shortcuts, Focus Border, Menu Bar, Quick App Shelf, and Workspaces. Use the
  selected compact dark Mission Control shell, WindowRanger's canonical robot, and one purposeful
  illustration per stage. Each configurable stage must read and mutate the same SettingsStore value
  used by the running app; Settings remains the later editing surface.
- **Ownership boundary:** Onboarding progress and completion are versioned, local-only application
  state. They are not profile content and are never sent through iCloud. Setting choices retain
  their existing global, profile, or machine-local ownership. A separate coordinator owns step
  navigation and completion; the wizard must not duplicate engine or profile serialization.
- **Acceptance:** A new install sees the wizard after runtime initialization; an incomplete wizard
  resumes safely; completion does not reappear for the same version. Back/Continue flows work
  with keyboard and mouse. The wizard can opt into iCloud, change both shortcut-family modifiers,
  preview/toggle/change Focus Border, preview/select menu-bar presentation, choose ordered Shelf apps
  or leave Shelf setup for later, and teach keyboard/swipe workspace navigation. Existing users with
  no onboarding marker receive the wizard because there has not yet been a public release. Pure
  state/action tests, the complete isolated suite, an unsigned universal build, signed installed-app
  interaction, and visual
  comparison against the selected mock are required before Done. General Settings exposes a
  searchable repeat-setup action that closes Settings before restarting at Welcome, preserves every
  existing configuration choice, and resumes normally if the repeated walkthrough is left incomplete.
- **Result:** A dedicated fixed native window now presents the seven versioned, resumable stages
  after runtime setup. Its controls mutate the existing SettingsStore owners directly. Onboarding
  keeps only version-namespaced progress locally; completion of one version cannot suppress or
  resume midway through a newer flow. The Shelf stage adds, removes, reorders, caps, and reports up
  to four profile-owned apps. Seven canonical-Ranger ImageGen scenes are bundled behind native UI.
- **Automated and visual evidence:** 22 August 2026 — all 673 isolated tests pass, including six
  focused onboarding state/action tests and the opt-in seven-stage production renderer. The
  unsigned Release app builds successfully for `arm64` and `x86_64`. All seven 1,960 x 1,320 dark
  production renders were inspected against the selected Mission Control reference; `design-qa.md`
  records the resolved asset-bundle, clipping, Shelf-order/capacity, and version-resume findings
  with no remaining scoped P0/P1/P2 mismatch. A skeptical read-only review reported no P0 and its
  three P1/P2 findings were corrected and reverified.
- **Installed evidence:** 23 August 2026 — signed universal daily revision
  `98d12d5fe02a-dirty` was installed at `/Applications/WindowRanger.app`, passed strict deep
  signature verification, matched the tested build bundle exactly, and resumed as the running
  application. The versioned first-run flow launched and persisted progress through step 5.
- **First-trial feedback and correction:** 23 August 2026 — the maintainer accepted the imagery and
  reported non-trailing iCloud/Focus switches, inert shortcut-family dropdown choices, a dead area
  near menu-bar selection ticks, unnecessary Shelf Skip affordance/copy, and an overly artificial
  thick left card accent. The corrected view uses explicit trailing switches, native menus containing
  only modifier combinations valid against the other family, non-hittable decorative strokes over
  full-row menu-bar buttons, clearer Shelf purpose/later-Settings copy without Skip, and a quiet
  accent wash with a uniform hairline instead of a left stripe. All 674 isolated tests pass,
  including valid onboarding shortcut-choice coverage, and all seven corrected production stages
  were rendered and inspected at 1,960 x 1,320.
- **Corrected install evidence:** 23 August 2026 — the refreshed signed universal daily revision
  `98d12d5fe02a-dirty` (CDHash `3e7df86750881ad6a3c2847f2fb9450c8428e6ca`) passed strict deep
  signature verification, matched the tested build bundle exactly, and resumed from
  `/Applications/WindowRanger.app`. The completed-version marker was intentionally preserved rather
  than silently resetting the maintainer's finished walkthrough.
- **Repeat-setup route:** 23 August 2026 — after the completed first trial showed there was no route
  back into the wizard, General Settings gained a searchable **Run Setup Again…** action. It closes
  the coordinator-owned Settings window, resets only versioned local onboarding progress, and
  presents Welcome on the next main-loop turn; profiles and current setting values remain intact.
  All 678 isolated tests pass, including ordered Settings dismissal before presentation, exact
  Settings-surface dismissal, search routing, preservation of global and profile-owned values, and
  resume from an interrupted repeated walkthrough. The unsigned Release app builds successfully
  for `arm64` and `x86_64`. Normal, dark, and compact production Settings renders show the new
  Setup section without clipping.
- **Repeat-route install evidence:** 23 August 2026 — signed universal Release daily revision
  `98d12d5fe02a-dirty` (CDHash `3b8fe6bd8973d7e14c7c43ee51fce206b21b0d86`) passed strict deep
  signature verification, matched the tested daily build bundle exactly, and resumed from
  `/Applications/WindowRanger.app`.
- **Repeat-route live finding:** The refreshed signed trial reopened at the correct saved stage, but
  mouse interaction remained unreliable for the compact shortcut menus and Focus Border switch even
  though footer navigation worked. Keyboard activation changed the live Focus Border setting, proving
  the SettingsStore binding was intact and narrowing the fault to the wizard's mouse targets. The
  corrective candidate gives switches their complete labelled row as a native hit target, gives each
  shortcut menu a visible minimum-size target, and activates the app before making the wizard key and
  main. All 678 isolated tests still pass, all seven production stages render without clipping, and
  the unsigned Release app builds successfully for `arm64` and `x86_64`. Refreshed signed mouse
  validation is required.
- **Control-target install evidence:** 23 August 2026 — signed universal Release daily revision
  `98d12d5fe02a-dirty` (CDHash `7619db47ae6e6582259716bd59ce067e86ad2717`) passed strict deep
  signature verification, matched the tested daily build bundle exactly, and resumed from
  `/Applications/WindowRanger.app`. The maintainer confirmed that this candidate still failed: only
  the exposed left edge of each shortcut menu responded, while the trailing Focus Border switch and
  colour well remained inert. Live accessibility geometry then identified the actual deterministic
  fault: the unconstrained decorative artwork owned a 702-point hit surface beginning 101 points
  inside the 480-point controls column. It covered every trailing body control but ended above the
  footer, exactly matching the observed split. The next candidate constrains artwork to the remaining
  right column, clips that column, makes the decorative surface pointer-transparent, and restores the
  earlier native shortcut-menu appearance. All 678 isolated tests pass, all seven corrected stages
  render cleanly, and the unsigned Release app builds successfully for `arm64` and `x86_64`.
  Refreshed signed mouse validation is required.
- **Artwork-boundary install evidence:** 23 August 2026 — signed universal Release daily revision
  `98d12d5fe02a-dirty` (CDHash `fd7fa8f927043306bd5e391d621bb792cf6c3fc7`) passed strict deep
  signature verification, matched the tested daily build bundle exactly, and resumed from
  `/Applications/WindowRanger.app`. The maintainer confirmed the complete visible shortcut-menu
  targets, Focus Border switch, and colour picker all respond correctly in this installed build.
- **Live boundary:** The first-run gate, app activation/Space placement, Accessibility permission
  handoff, keyboard traversal, application picker, resume after closing, and final completion still
  require explicit maintainer validation before Done.

### WR-069 — Wrap directional focus at workspace and Shelf edges

- **Type:** Navigation consistency improvement
- **Priority:** P1
- **Status:** Done — automated, signed installed-app, and maintainer interaction validation complete.
- **Requested:** 22 August 2026.
- **User-observed context:** After making Navigate arrows work inside the Quick App Shelf, edge
  containment felt inconsistent with cycling through an ordered set of applications. The expected
  rule applies to the other workspace layouts too: reaching the start or end should continue from
  the opposite edge.
- **Smallest useful outcome:** Preserve nearest-neighbour spatial focus when a target exists in the
  requested direction. At an outer edge, wrap to the opposite spatial edge within the same active
  workspace and interaction display, preferring candidates aligned on the perpendicular axis. In
  an open Shelf, wrap only along its visible layout axis; perpendicular arrows remain contained.
- **Acceptance:** Freeform, Tiled, Accordion, and both Shelf styles wrap in all applicable
  directions without crossing display/workspace admission boundaries. Direct neighbours remain
  preferred over wrap targets, Shelf arrow promotion does not relayout membership, and diagnostics
  distinguish a wrapped choice. Focused navigation/Shelf tests, the complete isolated suite, an
  unsigned universal build, skeptical review, and signed installed-app validation are required.
- **Result:** Navigate-arrow focus now keeps its nearest spatial neighbour first and, only at an
  outer edge, chooses the opposite edge of the same workspace and display. Shelf navigation uses
  the same fallback along its presentation axis while perpendicular arrows remain contained; the
  Command Palette advertises exactly those available Shelf directions. Arrange-arrow reordering is
  deliberately unchanged and does not wrap.
- **Automated evidence:** 22 August 2026 — 25 focused keyboard-navigation tests and 25 focused Shelf
  tests passed; the complete isolated suite passed all 683 tests; `git diff --check` passed; and the
  unsigned Debug app built successfully as universal `x86_64 arm64`. Skeptical rereview reported no
  P0-P2 finding. Live Accessibility focus behavior in the signed installed app remains unverified.
- **Installed evidence:** 22 August 2026 — the signed universal daily build
  `29117f974de9-dirty` was installed at `/Applications/WindowRanger.app`, its executable and debug
  dylib matched the built candidate, the Apple Development signature and Team ID `44NAD22AK6` were
  verified, and it resumed from the installed path. The maintainer then confirmed edge wrapping
  works in the installed app.

### WR-068 — Unify global shortcuts into configurable Navigate and Arrange families

- **Type:** Shortcut architecture and usability change
- **Priority:** P1
- **Status:** Live validation — implementation, cleanup, automated verification, and skeptical
  review complete; the cleaned signed app still needs interaction validation.
- **Requested:** 22 August 2026.
- **User-observed context:** Nearly every frequent WindowRanger command should begin with one of two
  learnable modifier prefixes. The current defaults are spread across Control-Option,
  Option-Command, Option-only and Option-Shift, while the Shortcut Guide exposes only the first two
  families. Numbered workspaces are the expected default; lettered workspace keys remain supported
  when they do not conflict with a family action key.
- **Smallest useful outcome:** Store one configurable **Navigate** modifier family and one
  configurable **Arrange** modifier family, then assign commands and workspaces a key suffix rather
  than independently recorded complete chords. Changing a family prefix updates every command in
  that family and the passive guide. A workspace owns one suffix: Navigate plus that key switches to
  it, while Arrange plus that key sends the focused window to it.
- **Approved defaults:** Navigate is Control-Option; Arrange is Option-Command. Preserve the direct
  workspace pair, Control-Option bracket workspace traversal, Control-Option Tab back-and-forth,
  Control-Option Space palette and Control-Option backtick Quick App. Use Navigate arrows for
  directional focus and Arrange arrows for reorder/corner placement; Navigate comma/period for
  previous/next window (and open-Shelf traversal); Arrange comma/period for Accordion/Tiled;
  Arrange minus/equal for resize; Arrange F for Floating; and Arrange D for moving the current
  workspace to the next display. There is no dedicated Cycle Quick Apps binding because
  Previous/Next Window already routes through an open Shelf and the palette exposes explicit
  Previous/Next Quick App commands. No Full Screen command is introduced by this remap.
- **Conflict boundary:** Family modifiers must be distinct exact combinations with at least two
  supported modifiers and no Fn/Globe. Key suffixes are unique within a family but may intentionally
  repeat across families. A workspace suffix reserves both of its derived family chords, so a
  conflicting action key must be remapped or unassigned before that workspace key can be used.
  Validate global action keys against every saved profile, not only the active one, and retain the
  existing fail-closed duplicate and macOS-registration handling.
- **Settings boundary:** Shortcuts owns the two global modifier families and key-only action map;
  Workspaces continues to own each profile workspace's one suffix and shows both resolved chords.
  These global shortcut choices retain the existing iCloud/global preference ownership and do not
  become profile content. Standard macOS Command-comma/Command-Q and contextual palette keys remain
  outside the families.
- **Acceptance:** Existing private-install full-chord data decodes safely into the approved map;
  changing either family regenerates all derived action/workspace chords, conflict reporting,
  Command Palette labels and Shortcut Guide observation/content without stale registrations.
  Focused persistence/conflict/registration/guide/Settings tests, the complete isolated suite and a
  universal unsigned app build must pass before signed live validation.
- **Result:** Shortcuts now stores configurable Navigate and Arrange modifier prefixes plus key-only
  action suffixes. Workspace suffixes derive both switch and move chords, inactive profiles
  participate in conflict validation, and legacy/private or remotely synced conflicts preserve the
  workspace while leaving the colliding action available from the Command Palette. Settings, the
  Command Palette, Carbon registration and the passive Shortcut Guide all resolve the same map. The
  redundant standalone Cycle Quick Apps binding has been removed while open-Shelf window traversal
  and explicit palette cycling remain. Decoding drops its retired saved assignments. The unused
  H/J/K/L shortcut tables, Globe/Fn input monitor and preference, obsolete command-wheel press/hold
  preferences, and stale user-facing wording have also been removed; stale local values are
  discarded without contacting iCloud, and their cloud copies are removed only during enabled sync.
- **Automated evidence:** On 22 August 2026, the two focused preference-migration/cloud-isolation
  regressions passed; test isolation passed; the complete suite passed with 666 tests and zero
  failures; `git diff --check` passed; and the unsigned universal Debug app built with both arm64
  and x86_64 slices. Skeptical rereview reported no P0-P2 finding.
- **Installed candidate:** After the shortcut cleanup, the signed universal Debug daily build
  `29117f974de9-dirty` was installed at `/Applications/WindowRanger.app` on 22 August 2026. Its
  executable and debug dylib matched the built candidate, its Apple Development signature and Team
  ID `44NAD22AK6` were verified, both `x86_64` and `arm64` slices were present, and the installed path
  was running. Interaction acceptance remains pending.
- **Live validation needed:** In the signed daily app, change each family prefix and a few action
  suffixes, confirm registrations and guide content update immediately, verify workspace conflict
  messages across active and inactive profiles, and exercise mouse and keyboard editing in
  Settings. Confirm an unassigned action stays searchable and runnable in the Command Palette, the
  Shelf still cycles through Previous/Next Window and its explicit palette commands, and no retired
  Cycle Quick Apps or Globe/Fn setting remains visible.

### WR-067 — Show a passive shortcut guide while navigation modifiers are held

- **Type:** Shortcut discoverability and usability feature
- **Priority:** P1
- **Status:** Done — selected option 3, corrected navigation-row spacing, and both modifier-family
  presentations were accepted in the signed installed app on 22 August 2026. WR-068 now owns the
  follow-up work to make those families configurable.
- **Requested:** 22 August 2026.
- **User-observed context:** Most WindowRanger use follows two related shortcut families:
  Control-Option for navigation and Option-Command for sending the focused window. Numbered
  workspaces are the common default, while arbitrary single-letter workspace keys must remain a
  first-class supported configuration.
- **Smallest useful outcome:** When either exact modifier family is held, show a passive,
  click-through, nonactivating Liquid Glass shortcut guide on the interaction display. Use the
  selected low, wide key-map direction: workspace destinations are the visual anchor and every
  other valid action using that modifier family is shown compactly. Derive content from the actual
  conflict-checked shortcut registry and current profile rather than maintaining a second command
  list. Releasing either required modifier, adding an incompatible modifier, recording shortcuts,
  entering a protected full-screen session, sleeping, resigning the session, or terminating must
  dismiss the guide without consuming input or changing focus.
- **Settings boundary:** Add a dedicated **Shortcut Guide** destination with local enablement, Small,
  Medium, or Large size, and a nine-position screen anchor. These screen-covering and passive-input
  preferences stay on this Mac; they do not belong to a reusable profile or iCloud sync payload.
- **Acceptance:** Control-Option and Option-Command each show only actions that can actually dispatch,
  numbered and lettered workspaces fit the same visual grammar, and conflicts/runtime registration
  failures are omitted. The panel never becomes key/main, activates WindowRanger, participates in
  window cycling, intercepts pointer/keyboard input, or remains stuck after a missed lifecycle
  transition. Geometry clamps safely on every connected display and at supported sizes/positions.
  Deterministic modifier/content/geometry/lifecycle tests, native Light/Dark visual comparisons,
  Settings search/navigation/persistence coverage, the complete non-hosted suite, and a universal
  app build are required before a signed live modifier/input check.
- **Automated evidence:** On 22 August 2026, the isolated non-hosted suite passed all 663 tests. The
  focused guide suite covers exact modifier families, conflicts and registration failures, lettered
  workspaces, mixed custom directional families, all geometry anchors, stale-session generations,
  the real passive panel policy, monitor start/stop and local Settings persistence. A follow-up
  skeptical review added exact Globe/Fn rejection, interaction-display precedence over a pointer on
  another monitor, and adaptive rows for every supported workspace key plus dense custom actions.
  The unsigned Debug app built as a universal arm64/x86_64 binary.
- **Visual evidence:** Native Light/Dark navigation and movement renders were compared beside the
  selected 1,487 x 1,058 option-3 target at matched state and placement. The final Large view is
  1,200 x 286 points; the production structure uses real system material/SF Symbols and ships no
  generated bitmap. `design-qa.md` records the focused and full-view evidence with a passed result.
- **Remaining boundary:** The diagnostic signed candidate now presents both modifier families and
  preserves input/focus in live use. The navigation guide's nine-workspace primary row was observed
  collapsing to its intrinsic width and bunching its keycaps at the left edge; the source candidate
  now makes that grid consume the available primary band. Install and live-check the corrected
  spacing, real Liquid Glass, press/release feel and interaction-display placement across the
  maintainer's multi-monitor layout.
- **User-observed live defect:** After installing the hardened candidate and enabling the guide on
  22 August 2026, holding either advertised modifier family showed no visible panel. Preferences
  confirmed enablement, size and position persisted; the process was running the expected signed
  dirty universal build and no monitor-start failure was recorded. The diagnostic candidate records
  only the resolved modifier family, truthful action counts, shortened display identifier and final
  panel visibility without recording keystrokes. Its logs confirmed both presentation paths and the
  maintainer subsequently confirmed the guide was visible; the initial absence was not reproduced
  again, so no unsupported root cause is claimed.

### WR-066 — Split overloaded Settings into clearer destinations

- **Type:** Settings information-architecture improvement
- **Priority:** P1
- **Status:** Live validation — the ownership pass is implemented and verified in isolation; a
  signed install still needs the maintainer's interaction check.
- **Requested:** 21 August 2026.
- **Smallest useful outcome:** Keep General focused on permissions and startup; give Sync, Menu Bar,
  and Focus Border their own destinations; and move recovery, focus-following moves, trackpad
  switching, and application-unhide compatibility into Behavior. Keep Profiles,
  Workspaces, Applications, Quick App Shelf, Shortcuts, Command Palette, and Diagnostics as their
  existing destinations.
- **Acceptance:** The sidebar and Settings search route every retained control to its clearer
  destination at wide and compact sizes without changing persistence, syncing, profile ownership,
  or legacy destination routing. Obsolete standalone Globe/Fn and placement settings are absent and
  cannot leave an input monitor running from a saved preference. Automated navigation/search coverage, the
  full non-hosted suite, and the universal app build must pass before signed live validation.
- **Profile boundary:** This first pass changes navigation and presentation only. A separate follow-
  up will make profile-owned versus Mac-local settings more visible after this structure is
  validated.
- **Profile-ownership follow-up:** Preserve the accepted top-level destinations, but identify the
  active profile consistently in Workspaces, Applications, and Quick App Shelf; separate reusable
  profile definitions from this Mac's selection, triggers, and physical display bindings; disclose
  the exact iCloud boundary; and move local application-specific Focus Border overrides out of the
  profile-owned Applications editor. Removing or converting a profile App Rule must not delete a
  Mac-local Focus Border override for the same bundle identifier.
- **User-observed follow-up:** The first installed split was still too coarse. Sync, Menu Bar, and
  Focus Border should each stand alone, while the former Globe/Fn and standalone placement settings
  no longer describe the current Command Palette experience.
- **Second user-observed follow-up:** Selecting a profile in Settings currently activates it and can
  rearrange the live desktop merely to inspect or edit its reusable definition. Settings needs an
  independent edit target. Selecting, creating, or duplicating a library profile must not activate
  it; activation remains an explicit **Use Profile** action. Editing an inactive profile must update
  only that reusable definition and its local display bindings, without publishing active engine
  configuration or changing this Mac's manual/automatic selection state.
- **Third user-observed follow-up:** Once inactive profiles can be edited safely, Profiles no longer
  needs to contain every setting related to profiles. Keep it as the reusable library and explicit
  activation surface; move this Mac's automatic selection rules into **Profile Switching**, and move
  the selected profile's display roles plus this Mac's physical bindings into **Displays**. Move the
  selected profile's Unified/Independent mode from Workspaces to Displays, while keeping each
  workspace's Home Display assignment in Workspaces. Menu-bar icon choices remain in Menu Bar.
- **Fourth user-observed follow-up:** The ownership and behaviour now feel correct, but the
  full-width **Editing Profile** strip above Displays, Workspaces, Applications, and Quick App Shelf
  reads as an awkward second toolbar. Use the selected sidebar-owned visual direction: put the
  editing-profile selector and active/inactive action in the sidebar immediately above those four
  destinations, and let every profile-owned page begin directly with its own content.
- **Fifth user-observed follow-up:** The sidebar direction is accepted, with one final refinement.
  Make the profile selector the same full-row width as its destination rows; give each reusable
  profile a selectable icon; show that icon with its name in the selector and profile library; and
  edit both icon and name directly in Profile Status instead of through a profile-list pencil.
  Remove the sidebar **Use Profile** row so activation remains a Profile Status action rather than
  looking like another destination.
- **Sixth user-observed follow-up:** The signed candidate is functionally correct, but its fixed-
  width profile selector starts 16 points to the right of the destination-row bounds and is clipped
  at the sidebar edge. Compensate for the sidebar section's custom-row inset so the selector shares
  the exact left and right edges used by Displays and the other profile-owned destinations.
- **Seventh user-observed follow-up:** The aligned signed selector opens an **Editing Profile**
  submenu before showing the profiles, so it does not behave like a direct drop-down. Keep native
  picker selection and checkmarks, but render its choices inline in the outer menu so one click
  exposes the profile list without an intermediate navigation level.
- **Implemented:** Added General, Sync, Behavior, Menu Bar, and Focus Border destinations; collected
  reusable feature configuration beneath Configuration and global input surfaces beneath Controls.
  Settings search opens the owning destination. Saved Appearance selections resolve to Menu Bar,
  while the legacy Layouts destination resolves to Workspaces. Displays is now a current destination.
  The Command Palette page now contains only
  enablement and its shortcut. Legacy wheel preferences remain readable for compatibility, but the
  app no longer constructs the Globe/Fn controller or installs its event monitor.
- **Profile-ownership implementation:** The sidebar and Workspaces, Applications, and Quick App
  Shelf identify the profile being edited. Selecting, creating, or duplicating a library profile now
  changes only the Settings edit target; **Use Profile** remains the explicit manual activation.
  The selector is a full-row icon-and-name menu without a second activation row. Profile Status
  edits the reusable icon and name directly and retains the explicit activation action. Profile
  icons follow cloning, iCloud persistence, and portable transfer; older documents default safely
  to the generic profile symbol. Inactive edits persist reusable profile identity, workspaces,
  applications, shelf, display-role definitions/icons, and local role bindings without changing the
  live engine or selection state. Profiles is now the reusable library and explicit activation
  surface; Profile Switching owns this Mac's automatic
  rules; Displays owns the editing profile's display mode and role definitions plus this Mac's
  physical bindings. Menu Bar remains the only editor for the editing profile's display-role icon
  choices. Sync lists the supported synced and always-local
  categories and explains why a reliable synced-device list is unavailable. Focus Border owns
  local per-application corner-radius overrides independently of profile App Rules and Quick Apps;
  removing or converting an App Rule no longer erases that local correction.
- **Automated evidence:** The revised Settings/navigation selection passes 131 focused tests. The
  final profile-icon refinement passes 46 focused profile, transfer, and rendering tests, and the
  complete non-hosted suite passes 649 tests, including inactive-profile editing across workspaces,
  display mode, App Rules, Quick App Shelf, display roles/icons, and explicit activation. Search and
  migration coverage includes General, Sync, Behavior, Menu Bar, Focus Border, removal of obsolete
  controls, and legacy destinations. Production Settings renders pass across 40 wide, compact,
  Light, Dark, and accessibility-text snapshots; the
  inactive Profiles render visibly separates the selected **Travel** edit target from the active
  **Current Setup** profile. The unsigned Debug app builds successfully as a universal
  `x86_64 arm64` binary.
- **Profile-ownership automated evidence:** The complete isolated suite passes 644 tests. Coverage
  includes the new Settings search routes and preservation of a local Focus Border override when an
  App Rule is removed or converted into a Quick App. The production Settings render passes and
  captures 34 wide, compact, Light, Dark, and accessibility-text reference screens, including the
  profile context, split profile ownership, Sync inventory, Menu Bar role icons, Focus Border
  overrides, and Quick App Shelf. The unsigned Debug app builds successfully as a universal
  `x86_64 arm64` binary.
- **Ownership-redistribution automated evidence:** Profiles is limited to the reusable library and
  explicit activation; Profile Switching owns this Mac's automatic rules; Displays owns the edited
  profile's Unified/Independent mode and role definitions plus local physical bindings; Workspaces
  retains workspace definitions, layouts, and Home Display assignments. Settings search and legacy
  routing follow those owners. The complete isolated suite passes 647 tests, including a 24-test
  profile selection run proving that automatic rule edits and Resume Automatic can change the live
  profile without replacing an inactive Settings edit target. Production Settings renders pass for
  Profiles, Profile Switching, Displays, and Workspaces, and the unsigned Debug app builds as a
  universal `x86_64 arm64` binary.
- **Sidebar profile-context implementation:** The full-row editing-profile selector now lives once
  in the sidebar immediately above Displays, Workspaces, Applications, and Quick App Shelf. It shows
  the profile icon and name without an activation-like row beneath it. The four destinations begin
  directly with their own content, and Menu Bar derives its profile-owned display-role icon section
  from the same edit target without duplicating the selector or activation action.
- **Sidebar profile-context automated evidence:** The complete isolated suite passes 649 tests.
  Production Settings renders pass in Light, Dark, active-profile, inactive-profile, and minimum-
  window states, including compact Quick App Shelf and Profile Status icon/name coverage; the final
  attached-reference comparison found no actionable P0-P2 issue. The unsigned Debug app builds
  successfully as a universal `x86_64 arm64` binary.
- **Superseded sidebar profile-context installed evidence:** With explicit maintainer approval, signed
  universal Debug candidate `ba41222bb796-dirty` is installed and running from
  `/Applications/WindowRanger.app` as process `32198`. The installed executable, debug dylib, and
  preview dylib match the built candidate exactly; strict signature validation, Apple Development
  authority, Team ID `44NAD22AK6`, canonical bundle identifier, embedded source marker,
  `x86_64 arm64` architectures, running path, and CDHash
  `818e149c8a267a090cf17b0668dffbfbaa5137d9` were verified. The previous daily build remains
  recoverable at `/Applications/.WindowRanger.previous` without an `.app` suffix.
- **Selector-alignment automated evidence:** The custom menu now compensates for the sidebar
  section's 16-point content inset while retaining the established 220-point destination-row
  width. The native production Settings snapshot passes, and the live-reference/corrected-render
  comparison confirms matching left and right bounds with Displays in Dark appearance.
- **Superseded selector-alignment installed evidence:** With explicit maintainer approval, the corrected signed
  universal Debug candidate `ba41222bb796-dirty` is installed and running from
  `/Applications/WindowRanger.app` as process `39349`. The installed executable, debug dylib, and
  preview dylib match the built candidate exactly; strict signature validation, Apple Development
  authority, Team ID `44NAD22AK6`, canonical bundle identifier, embedded source marker,
  `x86_64 arm64` architectures, running path, and CDHash
  `f1ddff740409b22095cf3259b54d2781e0006ef9` were verified. The previous daily build remains
  recoverable at `/Applications/.WindowRanger.previous` without an `.app` suffix.
- **Direct-menu automated evidence:** The selector's nested picker now uses SwiftUI's inline picker
  style, retaining native selection/checkmark semantics while placing its profile choices directly
  in the outer menu. Test isolation, the native closed-state production snapshot, and the unsigned
  universal Debug build pass. The open-menu interaction remains signed live validation.
- **Direct-menu installed evidence:** With explicit maintainer approval, signed universal Debug
  candidate `ba41222bb796-dirty` is installed and running from `/Applications/WindowRanger.app` as
  process `43117`. The installed executable, debug dylib, and preview dylib match the built candidate
  exactly; strict signature validation, Apple Development authority, Team ID `44NAD22AK6`, canonical
  bundle identifier, embedded source marker, `x86_64 arm64` architectures, running path, and CDHash
  `06d672dcd4d6e4d059171ade742b49e7dd18767f` were verified. The previous daily build remains
  recoverable at `/Applications/.WindowRanger.previous` without an `.app` suffix.
- **Profile-ownership installed evidence:** With explicit maintainer approval, signed universal
  Debug candidate `ba41222bb796-dirty` is installed and running from
  `/Applications/WindowRanger.app` as process `43469`. The installed executable and Debug/preview
  dylibs match the built candidate exactly; strict signature validation, Apple Development
  authority, Team ID `44NAD22AK6`, canonical bundle identifier, embedded revision, `x86_64 arm64`
  architectures, running path, and CDHash `e8f601032e717b69b9ad1057e83a05f07c882515`
  were verified. The previous daily build remains recoverable at
  `/Applications/.WindowRanger.previous` without an `.app` suffix.
- **Superseded installed evidence:** With explicit maintainer approval, the first signed universal Debug candidate
  `ba41222bb796-dirty` is installed and running from `/Applications/WindowRanger.app` as process
  `97787`. The built and installed executable, debug dylib, and preview dylib match exactly; the
  Apple Development signature, Team ID `44NAD22AK6`, canonical bundle identifier, embedded source
  marker, `x86_64 arm64` architectures, running path, and CDHash
  `420c4839e826912b9ec17833c4a2a44320773439` were verified. The previous daily build remains
  recoverable at `/Applications/.WindowRanger.previous` without an `.app` suffix.
- **Revised installed evidence:** With explicit maintainer approval, signed universal Debug candidate
  `ba41222bb796-dirty` is installed and running from `/Applications/WindowRanger.app` as process
  `13055`. The built and installed executable, debug dylib, and preview dylib match exactly; the
  Apple Development signature, Team ID `44NAD22AK6`, canonical bundle identifier, embedded source
  marker, `x86_64 arm64` architectures, running path, and CDHash
  `3347c05a2273770b3eba321bf1d9b9ec3e93f99d` were verified. The previous daily build remains
  recoverable at `/Applications/.WindowRanger.previous` without an `.app` suffix.
- **Ownership-redistribution installed evidence:** With explicit maintainer approval, signed
  universal Debug candidate `ba41222bb796-dirty` is installed and running from
  `/Applications/WindowRanger.app` as process `51209`. The installed executable, debug dylib, and
  preview dylib match the built candidate exactly; strict signature validation, Apple Development
  authority, Team ID `44NAD22AK6`, canonical bundle identifier, embedded source marker,
  `x86_64 arm64` architectures, running path, and CDHash
  `1b3fdad193559f32972fb6303440132c00e89e38` were verified. The previous daily build remains
  recoverable at `/Applications/.WindowRanger.previous` without an `.app` suffix.
- **Live evidence:** On 21 August 2026, the maintainer accepted the revised section structure as
  better and easier to navigate in the signed installed app.
- **Live validation remaining:** Confirm in the installed direct-menu candidate that the aligned
  full-row selector opens profile choices immediately and changes only the edit target; profile
  icon/name editing and the Profile Status **Use
  Profile** action work as expected; long profile names and the supported minimum window remain
  usable; and pointer/keyboard/VoiceOver interaction opens the native menu reliably. Recheck that
  Profiles stays a quiet library and that Menu Bar role icons, Displays,
  Workspaces, Applications, and Quick App Shelf all follow the selected edit target without
  restoring the removed page-level context strip.

### WR-065 — Put the current workspace layout at the top of Command Palette

- **Type:** Command Palette interaction improvement
- **Priority:** P1
- **Status:** Up-to-Quick-Actions and search-hiding follow-up installed; signed live keyboard and
  pointer validation pending.
- **User-observed:** Removing the Command Wheel also removed the easiest discoverable way to switch
  a workspace back to Freeform. Tiled and Accordion have default shortcuts, but Freeform does not.
- **Installed regression observed:** The first signed candidate changes to Freeform and immediately
  exposes its valid Placement Halo, but choosing a position does nothing until the palette is closed
  and reopened. Diagnostics confirm the layout and halo succeed, then the placement is rejected as
  `stale-context`; reopening captures the settled post-layout token and the same placement succeeds.
- **Second installed regression observed:** The corrected candidate reaches placement dispatch, but
  an open Quick App Shelf can restore its selected shelf window before the queued placement commits.
  Diagnostics then show `freeform-placement-rejected` with `runtime-context-changed`. A rapid series
  of layout choices can also leave the visible placement command carrying an older token even when
  the controller's surrounding context has already settled.
- **Third installed regression observed:** The second-correction candidate still rejects placement
  as `stale-context`. Fresh diagnostics show palette dismissal briefly reports no focused AX window
  before revalidation, so the validation request loses the preserved managed anchor before it can
  dispatch. The same session also records a separate, genuine `toggle-drop-down-app` hotkey event
  while the palette is open; the unexpected Shelf presentation did not originate from palette
  selection or placement dispatch.
- **Escape regression observed:** The latest installed candidate fixes immediate post-layout
  placement, but Escape can bring a retained Shelf window to the foreground even when another app
  preceded the palette. Diagnostics show `presented-shelf-focus-restored` selecting the startup-
  retained Ghostty session. Shelf restoration must require the preceding application's PID to match
  the presented Shelf window; otherwise dismissal returns to the actual preceding app.
- **Smallest useful outcome:** Show a compact Quick Actions block directly beneath Command Palette
  search. Stack the current workspace's Freeform/Tiled/Accordion control above a focused-window
  placement row, keeping their different scopes explicit and the command list primary. Omit the
  placement row when no truthful placement exists. Tab or Up from the first command enters Quick
  Actions; Up/Down moves between rows, Left/Right changes layout only on the workspace row, Return
  opens placement, and Escape returns to command search/results. Starting a search hides Quick
  Actions and an open Halo until the query is cleared.
- **Terminology boundary:** Use **Freeform**, not Floating. Freeform is the workspace layout;
  Floating remains the separate per-window override.
- **Acceptance:** Quick Actions target the palette's current interaction workspace and focused
  window without conflating them. Pointer and keyboard paths remain available, command-result
  Up/Down behavior remains unchanged, typing resumes filtering, and unavailable placement is absent
  rather than disabled. Layout dispatches through the shared typed command path, remains usable
  through repeated changes, refreshes palette context after each accepted change, and still rejects
  or closes on an unrelated stale context. Accessibility labels, diagnostics, tests, the production
  offscreen render, and the universal app build must pass before signed live validation.
- **Implemented:** A compact Quick Actions block stacks the current interaction workspace's
  Freeform/Tiled/Accordion control above a conditional Place focused window row. Tab or Up from the
  first command enters the block at the appropriate edge; Up/Down moves between rows, Left/Right
  changes layout only on the workspace row, and Return opens placement from its row. Escape restores
  command handling. A nonempty query hides Quick Actions and collapses an open Halo until cleared.
  Pointer selection and keyboard changes keep the palette open, while an unavailable placement row
  is omitted. Accepted layout changes refresh the palette's
  captured context, while unrelated workspace/context changes retain the existing fail-closed
  dismissal behavior. A post-layout action is checked against a fresh engine context and placement
  tokens are rebound only when the exact window, workspace, layout, display topology, and profile
  remain unchanged. Placement commits are enqueued before palette dismissal restores Quick App or
  fallback focus. The latest correction validates and queues placement while the palette's preserved
  target is still authoritative, treats a transient nil AX focus as palette-owned, then dismisses
  the palette and restores focus in serial order. Escape restores a presented Shelf window only
  when its application genuinely preceded the palette, not merely because a Shelf session remains
  retained.
- **Automated evidence:** The complete 643-test non-hosted suite passes with focused Quick Action
  availability/navigation, Up-from-first-result entry, nonempty-search hiding, layout-only
  horizontal movement, settled/older-token rebinding,
  changed-window/layout rejection, deferred placement focus restoration, palette-owned transient
  nil-focus coverage, and preceding-app-gated Shelf
  restoration, alongside test-isolation, project-regeneration, shell-syntax, and diff checks. The
  production-view offscreen snapshots render available, omitted-placement, and placement-only Quick
  Actions, and the expanded Placement Halo follows its row without obscuring the layout control. The
  actual unsigned Debug app target builds successfully as a universal `x86_64 arm64` binary.
- **Current installed evidence:** With explicit maintainer approval, the compact Quick Actions
  signed universal Debug candidate `9828628787b7-dirty` is installed and running from
  `/Applications/WindowRanger.app` as process `84435`. The built and installed executable, debug
  dylib, and preview dylib match exactly; the Apple Development signature, Team ID `44NAD22AK6`,
  canonical bundle identifier, embedded source marker, `x86_64 arm64` architectures, running path,
  and CDHash `28f07ff8da7488d3266c086bc98352d3908a42f5` were verified. The immediately
  preceding candidate remains recoverable at `/Applications/.WindowRanger.previous` without an
  `.app` suffix. Live validation of Up-from-first-result and search-hiding behavior remains pending.
- **Sixth superseded installed evidence:** With explicit maintainer approval, the first compact
  Quick Actions signed universal Debug candidate `9828628787b7-dirty` was installed and running
  from `/Applications/WindowRanger.app` as process `80874`. The built and installed executable,
  debug dylib, and preview dylib matched exactly; the Apple Development signature, Team ID
  `44NAD22AK6`, canonical bundle identifier, embedded source marker, `x86_64 arm64` architectures,
  running path, and CDHash `a13376eadc3cf5d11ccfac1472177cff15b438b4` were verified. This
  candidate predated the Up-to-Quick-Actions and search-hiding follow-up.
- **Fifth superseded installed evidence:** With explicit maintainer approval, the Escape-correction signed
  universal Debug candidate `9828628787b7-dirty` is installed and running from
  `/Applications/WindowRanger.app`. The built and installed executable, debug dylib, and preview
  dylib match exactly; the Apple Development signature, Team ID `44NAD22AK6`, canonical bundle
  identifier, embedded source marker, both architectures, running path, and CDHash
  `dabcc8d451bbadf7328d96d2a1879e307d3966d6` were verified. The immediately preceding candidate
  remains recoverable at `/Applications/.WindowRanger.previous` without an `.app` suffix.
- **Fourth superseded installed evidence:** With explicit maintainer approval, the placement-
  correction signed universal Debug candidate `9828628787b7-dirty` is installed and running from
  `/Applications/WindowRanger.app`. The built and installed executable, debug dylib, and preview
  dylib match exactly; the Apple Development signature, Team ID `44NAD22AK6`, canonical bundle
  identifier, embedded source marker, both architectures, running path, and CDHash
  `a47a5af7464f99fc548a24c80195b3b09d002b1b` were verified. The immediately preceding candidate
  remains recoverable at `/Applications/.WindowRanger.previous` without an `.app` suffix. Live use
  accepts immediate post-layout placement but exposed the Escape Shelf restoration regression, so
  this candidate is not acceptance evidence for the Escape correction.
- **Third superseded installed evidence:** With explicit maintainer approval, the second-correction
  signed universal Debug candidate `9828628787b7-dirty` is installed and running from
  `/Applications/WindowRanger.app`. The built and installed executable, debug dylib, and preview
  dylib match exactly; the Apple Development signature, Team ID `44NAD22AK6`, canonical bundle
  identifier, embedded source marker, both architectures, running path, and CDHash
  `041e8ad33b1c4cc96f9dbd200f1906c9cb0d5543` were verified. The immediately preceding candidate
  remains recoverable at `/Applications/.WindowRanger.previous` without an `.app` suffix. Live use
  exposed the transient nil-focus rejection described above, so this candidate is not acceptance
  evidence for the latest correction.
- **Second superseded installed evidence:** With explicit maintainer approval, the corrected signed
  universal Debug candidate `9828628787b7-dirty` is installed and running from
  `/Applications/WindowRanger.app`. The built and installed executable and debug dylib match exactly;
  the Apple Development signature, Team ID `44NAD22AK6`, canonical bundle identifier, embedded source
  marker, both architectures, running path, and CDHash
  `fd584316919bbb2760a2f8fbb2ce65bbbe257a43` were verified. The superseded signed candidate is
  retained at `/Applications/.WindowRanger.previous` without an `.app` suffix. Live diagnostics show
  that this candidate can dispatch placement and still lose its anchor when shelf focus is restored
  first, so it is not acceptance evidence for the second correction.
- **Superseded installed evidence:** With explicit maintainer approval, the first signed universal
  Debug candidate `9828628787b7-dirty` is installed and running from
  `/Applications/WindowRanger.app`. The built and installed executable and debug dylib match exactly;
  the Apple Development signature, Team ID `44NAD22AK6`, canonical bundle identifier, embedded source
  marker, both architectures, running path, and CDHash
  `aec1bef572f7e3477526921aac988f515499c3a7` were verified. The previous daily copy remains
  recoverable at `/Applications/.WindowRanger.previous` without an `.app` suffix. Live use exposed
  the stale post-layout placement token described above, so this candidate is not acceptance
  evidence for the correction.
- **Live validation remaining:** In the signed installed app, verify pointer selection plus entry,
  repeated changes, and exit with Up, Left/Right, Down, Return, and Escape across Freeform, Tiled,
  and Accordion workspaces. Confirm the palette stays open, its selected segment follows accepted
  engine state, an immediately selected Freeform/Tiled placement runs without reopening, results
  remain usable, and an external workspace/context change still closes it.

### WR-063 — Give Quick App Shelf its own shared Settings section

- **Type:** Settings and profile-model change
- **Priority:** P1
- **Status:** Live validation
- **Requested:** 21 August 2026.
- **Smallest useful outcome:** Move Quick App Shelf out of the per-application inspector into its
  own Settings sidebar destination. The shelf owns edge, size, and animation once per profile;
  assigned apps retain only stable bundle identity, display name, and order.
- **Migration boundary:** Existing profiles deterministically adopt the first configured entry's
  presentation values as the shared shelf settings. Legacy single-Quick-App profiles retain their
  exact behavior. Machine-local selected identity never influences synced migration.
- **Acceptance:** Add, remove, and reorder shelf apps in the dedicated section; no app row exposes
  contradictory presentation controls. Profile clone, export/import, iCloud validation, legacy
  decoding, and Settings search preserve or discover the shared shelf configuration. Automated
  tests and a universal app build pass before signed live validation.
- **Implemented:** Quick App Shelf is now a dedicated Settings destination. Edge, size, and
  animation are one profile-owned presentation applied uniformly to every ordered shelf entry;
  Applications now lists only normal App Rules. Existing profiles migrate the first configured
  entry's presentation, and portable transfer plus iCloud validation preserve the shared setting.
- **Automated evidence:** The complete 630-test non-hosted suite, test-isolation check, project
  regeneration, shell syntax checks, and an unsigned universal Debug app build pass. Signed-app
  visual and interaction validation remains.
- **Installed evidence:** With explicit maintainer approval, the signed universal Debug candidate
  for `9828628787b7-dirty` is installed and running from `/Applications/WindowRanger.app`. The built
  and installed executables match exactly, and the Apple Development signature, Team ID
  `44NAD22AK6`, bundle identity, embedded revision, both architectures, running path, and CDHash
  `3c4b90d922bd58d588cb00895a5607c1ada81218` were verified. Dedicated Settings layout and live
  profile migration/interaction remain for maintainer validation.

### WR-064 — Multi-window Quick App Shelf presentation

- **Type:** Feature / interaction design
- **Priority:** P1
- **Status:** Implementation and automated verification complete; signed live validation pending.
- **Requested:** 21 August 2026.
- **Direction:** Add shelf-owned Accordion and Carousel presentation styles plus a bounded visible
  app count. Cycling changes the selected entry while preserving the shelf as one coordinated
  presentation group.
- **Semantics:** Accordion overlaps the visible entries inside the shelf bounds with the
  selected window foremost and a fixed reachable edge for its neighbours. Carousel lays the visible
  entries out as non-overlapping cards along the edge's cross-axis, centred around the selected
  entry. The visible count is capped by the four-entry shelf.
- **Decision:** On 21 August 2026, the maintainer chose the non-launching option: visible count is a
  maximum over configured apps that already expose one unambiguous available window. Opening or
  cycling may still launch the explicitly selected app through the existing bounded path, but never
  launches neighbours merely to fill the group. Proceed with the proposed Accordion overlap and
  non-overlapping Carousel geometry.
- **Acceptance boundary after decision:** Exact ownership remains per window; ambiguous apps fail
  closed without disturbing valid neighbours; focus, palette cycling, application Hide ownership,
  profile changes, native-tab replacement, sleep/wake, and removal restore every member safely.
- **Implemented:** The dedicated shelf presentation now includes Carousel and Accordion styles plus
  a one-to-four visible maximum. The engine resolves only already available, unambiguous neighbour
  windows, gives each member exact session and confirmed Hide/Unhide ownership, lays the group out
  within focus-border-aware bounds, and keeps the selected window raised. Choosing or cycling to an
  already visible member promotes it without collapsing the shelf; moving outside the visible group
  safely transitions to the new selection. Navigate-arrow focus treats the presented group as a
  contained temporary workspace, promotes the nearest visible member in that direction, and wraps
  to the opposite visible edge without falling through to a managed window. Perpendicular arrows
  remain contained. Comma/period retains ordered wrapping. Legacy
  profiles default to the existing one-window
  Carousel behavior, and profile clone/export/import/iCloud paths preserve and validate both fields.
- **Automated evidence:** The complete 633-test non-hosted suite passes alongside test-isolation,
  project-regeneration, shell-syntax, and diff checks. Focused coverage exercises group membership,
  both geometries, Settings persistence/search, legacy defaults, transfer round-trip, and invalid
  synced/imported counts. The unsigned Debug app builds successfully as a universal `x86_64 arm64`
  binary. Signed multi-app interaction and lifecycle validation remain pending.
- **Directional-focus automated evidence:** Focused Shelf and keyboard coverage passes 45 tests,
  including spatial selection and edge containment for Carousel and Accordion on all four Shelf
  edges, one-window containment, and zero-presented transition containment. The complete isolated
  suite passes 678 tests with zero failures, the unsigned universal Debug build succeeds for
  `x86_64 arm64`, diff checks pass, and the post-fix review reports no remaining P0-P2 finding.
- **Directional-focus installed candidate:** With explicit maintainer approval, signed universal
  Debug candidate `29117f974de9-dirty` is installed and running from
  `/Applications/WindowRanger.app` as process `77182`. The built and installed executable and debug
  dylib match exactly; the Apple Development signature, Team ID `44NAD22AK6`, canonical bundle
  identifier, both architectures, running path, and CDHash
  `7cf259ed82964e757aef0558ad7174e07d521fe4` were verified. This installed candidate includes the
  in-place Left-arrow correction. The previous daily build remains
  recoverable at `/Applications/.WindowRanger.previous`.
- **Directional-focus live defect:** The installed two-window Accordion Shelf accepted Right but
  every Left press was contained as `no-shelf-target`. Diagnostics confirmed shortcut dispatch was
  correct: directional promotion unnecessarily reconciled the selected-centred visible group after
  every selection, moving the new target back to the first slot. The source now raises and focuses
  an already-presented arrow target in place without changing Shelf membership or frames. Focused
  regression coverage verifies Right followed by Left against fixed two-window Carousel and
  Accordion geometry; ordered comma/period cycling still owns off-group rotation.
- **Post-defect automated evidence:** Test isolation and diff checks pass; the complete non-hosted
  suite passes 679 tests with zero failures; the unsigned universal Debug app builds successfully
  for `x86_64 arm64`; and skeptical review reports no remaining P0-P2 finding. The corrected signed
  candidate is now installed; the Left-arrow interaction remains in live validation.
- **Installed evidence:** With explicit maintainer approval, the signed universal Debug candidate
  `9828628787b7-dirty` is installed and running from `/Applications/WindowRanger.app`. The built and
  installed executable and debug dylib match exactly; the Apple Development signature, Team ID
  `44NAD22AK6`, canonical bundle identifier, embedded source marker, both architectures, running
  path, and CDHash `c28d7a9b89ad18ce0f29d3786d50dd897f4946fe` were verified. The previous
  daily copy remains recoverable at `/Applications/.WindowRanger.previous` without an `.app` suffix.
- **Live validation remaining:** Exercise both styles at all four edges with two to four shelf apps;
  verify visible and off-group cycling, spatial arrow focus and edge wrapping with the palette
  both open and closed, palette focus retention, ambiguous neighbours, a closed selected app, focus
  loss, style/count changes while open, profile changes, native-tab replacement, sleep/wake,
  focus-border toggling, and safe restoration before moving this item to Done.

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
  bundle has either normal App Rules or one entry in the ordered Quick App Shelf, explicit confirmed
  conversion
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
  clear the session instead of guessing. Startup now claims every configured Quick App with one
  unambiguous eligible window before initial workspace layout and always begins that entry hidden;
  launching WindowRanger never implicitly presents a Shelf entry merely because it was already
  visible. Exact WindowRanger-owned hidden applications remain hidden, externally hidden
  applications remain untouched, and multiple matching windows remain unclaimed.
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

### WR-081 — Retain stable layout slots across transient Accessibility read failures

- **Type:** Layout stability bug
- **Priority:** P1
- **Status:** Automated implementation complete; signed-app and live-window validation remain.
- **Requested:** 24 August 2026.
- **Smallest useful outcome:** Preserve an existing Tiled or Accordion participant when its
  application enumeration fails or its frame is temporarily unreadable, without writing geometry to
  that participant or reflowing readable siblings around the observation gap.
- **Acceptance:** Successful enumeration absence, and authoritative minimized, fullscreen, ignored,
  floating, or App Rule layout-excluded states release the slot immediately. The change must preserve
  current window-admission semantics and all geometry-write safety gates.
- **Automated evidence:** Focused policy and layout coverage distinguishes non-authoritative read
  failures from authoritative removal/ineligibility and proves a retained slot does not become
  geometry-write eligible. Integration review added hidden-application, visibility/wake, and
  normal-window-to-floating-dialog regressions before release. On 24 August 2026, the focused
  `WorkspaceDefinitionTests` suite passed 125 tests, then stable Xcode passed all 723 non-hosted
  tests, static analysis, the unsigned universal Release build, and both DMG smoke layouts.
- **Remaining validation:** In a signed Debug candidate, exercise ordinary polling and transient
  dialog activity with multi-window Tiled and Accordion workspaces. Confirm no sibling double reflow,
  then confirm genuine close, minimize, fullscreen, floating, layout exclusion, workspace switching,
  and wake still release or retain slots as specified.
### WR-080 — Add the current application from Command Palette

- **Type:** Command Palette and application-configuration improvement
- **Priority:** P2
- **Status:** Implementation and automated verification complete; signed live validation pending.
- **Requested:** 23 August 2026 after installing the first Sparkle-capable Beta.
- **Smallest useful outcome:** For an eligible app owning the captured focused window, Command
  Palette offers searchable actions for the active profile's normal Applications list and App Shelf.
  An already assigned destination is omitted, conversion is labelled Move, and the Shelf action is
  omitted at its four-entry cap. Applications uses the captured workspace as the app's initial rule
  destination. WindowRanger, non-regular apps, and SurfaceLab's whole-application Shelf visibility
  restriction are excluded.
- **Safety boundary:** The palette carries the focused app's exact mutually exclusive membership,
  then the MainActor write fails closed if membership, capacity, workspace, or active-profile
  identity changes after dispatch. Editing a different Settings profile does not redirect the
  action, and a full Shelf cannot discard an existing App Rule.
- **Automated evidence:** Focused palette, dispatcher, Settings, and Shelf-policy tests cover
  searchable Add/Move labels, destination omission, capacity changes, exclusive conversion,
  active-versus-editing profile separation, post-dispatch membership races, stale profile
  rejection, and the SurfaceLab Shelf restriction. `./scripts/verify-local-ci.sh --quick` passed
  all 700 non-hosted tests on 24 August 2026.
- **Live validation remaining:** From an unconfigured ordinary app, verify both palette additions,
  both conversions, full-Shelf omission, captured workspace assignment, and behavior while Settings
  edits a different profile.
### WR-061 — Quick App Shelf

- **Type:** Feature / corrective overhaul
- **Priority:** P1
- **Status:** Implementation and automated verification complete; signed live validation pending.
- **Source:** `docs/omarchy-inspired-ideas.md`
- **User-observed:** The first signed shelf candidate exposed multiple Quick Apps in Settings and the
  Command Palette, but the feature was only partly functional and did not behave as a coherent
  shelf. In the corrected candidate, opening the Command Palette still closed a presented shelf
  entry, and the established Previous/Next Window shortcuts did not traverse an open shelf.
- **Review evidence:** The superseded implementation had two engine configuration publishers,
  reordered configured entries to store runtime selection, canceled an unchanged secondary-app
  launch on publication echo, made three/four-item cycling unstable, allowed transition generations
  to strand exact sessions, and made palette actions labelled Show toggle. A final independent diff
  review also found and prompted corrections for repeated cycling during one hide and an inactive
  shelf entry's native-tab handoff invalidating another entry's active animation.
- **Implemented:** One stable profile-owned ordered shelf now drives the engine. Per-profile selected
  identity is machine-local and never reorders synced configuration. Direct palette selection is
  idempotent Show; the established shortcut is Toggle selected; Previous/Next cycle from the latest
  desired selection. Launch/show/hide/switch intents are serialized, focus loss during Show queues a
  hide, screen suspension cancels transient intent while retaining exact recovery ownership, startup
  ignores persisted non-shelf sessions, and native-tab rebind invalidates animation only for the
  active or presented entry. Settings provides labelled add choices, visible reordering, per-entry
  editing/removal, a four-entry cap, and shelf-aware copy. Palette activation now holds an explicit
  focus lease so an open shelf remains visible; Previous/Next Window route through the shelf while
  it is presented, palette-owned previews retain keyboard focus, and palette dismissal focuses the
  currently presented entry.
- **Safety boundary:** Existing exact-window ownership, launch watchdog, ambiguity rejection,
  application hide/unhide confirmation, focus, placement, focus-border clearance, lifecycle
  recovery, and fail-closed admission remain authoritative. The engine never guesses among multiple
  windows or releases application-hidden ownership without confirmed recovery.
- **Automated evidence:** Fifteen focused shelf tests cover stable three/four-entry cycling,
  per-profile selection, legacy migration, persisted exact-session ownership, closed-secondary
  launch echo, idempotent direct Show, rapid transition policy, repeated in-flight cycling, and
  cross-entry native-tab handoff, plus palette focus preservation and open-shelf window-cycle
  routing. Related transfer and iCloud tests reject oversized or duplicate
  shelf data instead of silently trimming it. `./scripts/verify-local-ci.sh --quick` passes test
  isolation, script checks, project regeneration, and all 626 non-hosted tests. The actual app target
  also builds as an unsigned universal arm64/x86_64 Debug app. Final independent review reports no
  remaining actionable issue in the combined diff.
- **Live validation remaining:** Validate palette opening and Previous/Next Window shelf previews
  alongside two profiles, a closed secondary app, repeated cycling/direct selection, focus-loss
  hide, native-tab replacement, and lock/wake before moving this item to Done.
- **Current installed candidate:** The signed universal Debug candidate `9828628787b7-dirty` was
  installed and launched from `/Applications/WindowRanger.app` on 21 August 2026; its bundle
  identifier, signature, source marker, architectures, and running executable path were verified.
  After the palette focus-lease correction, a fresh approved install was matched byte-for-byte to
  the just-built executable before live handoff. User interaction evidence remains pending.
- **Previous candidate:** The superseded daily copy is retained at the repository-defined
  non-launchable backup path. Its 619 passing tests did not exercise the failing interaction
  sequences and are not acceptance evidence for this overhaul.

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
- **Additional diagnostic-backed report (2026-08-24):** In workspace 1, Claude and Chrome occupied
  only the left half of a four-window Tiled layout. Two unminimized Simulator device windows were
  parked at `(3839, 1568)` and still counted as layout participants. Both were layer-0
  `AXStandardWindow` surfaces with ordinary document controls, writable positions, and
  authoritatively read-only sizes. Their rejected initial size writes correctly stopped the frame
  sequence before position, but that safety behavior left them parked while they continued to
  reserve two tile slots.
- **Live evidence:** The signed Debug build classified the ChatGPT document window and updater as
  layer-0 `AXWindow` / `AXStandardWindow` surfaces. The document window exposed a Full Screen
  control. The 602 x 178 updater exposed Close but no Full Screen control; it accepted the requested
  position, rejected the requested size, and was then incorrectly reweighted into the Tiled tree.
  The Ghostty prompt was an `AXDialog` initially observed at WindowServer layer 8 with unsupported
  move/resize capability reads. It was admitted as an ambiguous normal window, rejected the requested
  size but accepted the position, and moved from `(1550, 314; 260 x 252)` to
  `(1683, 34; 260 x 252)`. Roughly 3.8 seconds later it reported layer 0 and was correctly floated,
  but its original position had already been lost; its layer then continued to alternate until close.
- **Expected:** Any ordinary layer-0 standard window proven movable but not resizable, with a Close
  control, floats automatically without using titles, dimensions, application-specific strings, or
  a whole-app exclusion. It must return on-screen through a position-only write and must not reserve
  a Tiled or Accordion slot; resizable windows from the same application remain in layout. An
  explicit dialog on a known nonzero transient layer remains untouched until its layer settles.
  Missing layers or failed capability reads remain conservatively managed as normal, and a rejected
  resize cannot still move a fixed-size surface.
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
  admission. A known
  nonzero-layer `AXDialog` is now deferred until its layer settles rather than being admitted to a
  layout. Frame application stops before position when its initial size write is rejected, preventing
  fixed-size surfaces from being partially moved after a failed resize. The 2026-08-24 correction
  broadens the one-time capability probe to every ordinary layer-0 standard window with a Close
  control. Authoritative writable-position/read-only-size evidence now floats the exact surface;
  unsupported, failed, or contradictory reads remain conservative, and a completed negative probe
  is retained instead of repeated on every refresh. Proven fixed-size surfaces use position-only
  writes during ordinary restoration, display changes, Quick App transitions, and quit recovery,
  and an explicit Arrange-F override cannot force them back into a resize-first layout path. If the
  discovery probe was inconclusive but a later initial size write rejects, a bounded re-probe
  converts that exact standard window to the same position-only safety path and immediately
  completes the move, then re-solves the visible layouts so the freed slot is filled in the same
  refresh. Position and final-size failures do not promote a normal document. This is
  capability-based rather than a Simulator profile, so other windows in the same app are unaffected
  when resizable.
- **Automated evidence:** Focused admission, workspace, diagnostics, and Quick App verification pass
  218 tests. Local quick verification passes all 693 non-hosted tests, including project
  regeneration, script and release workflow checks, and test-isolation validation; it does not
  build, launch, sign, install, stop, or automate WindowRanger.app. Fixtures cover the captured
  ChatGPT document/updater distinction, the captured Simulator device-window metadata, a
  non-Simulator fixed-size standard window, a resizable Simulator window, plus unavailable and
  immovable conservative fallbacks.
- **Live validation:** The signed Debug build from this branch kept the ordinary ChatGPT document
  window managed normally, classified the reopened Sparkle updater through the fixed-size path, and
  left the updater floating outside the Tiled tree. The user confirmed the result on 2026-08-14.
- **Follow-up live result:** The captured Ghostty confirmation prompt was reproduced against the
  changed signed app. It remained outside the managed split and retained its intended placement; the
  user confirmed the result before proceeding to the Quick App follow-ups. Other applications may
  expose different transient metadata, so the classifier remains fixture-backed and fail-closed
  rather than inferring from titles, dimensions, or broad application exclusions.
- **Installed diagnostic evidence (2026-08-24):** With explicit maintainer approval, the signed
  universal Debug candidate at `c5a576c09c43-dirty` replaced the installed daily copy and preserved
  Beta 7 build 8 as `/Applications/.WindowRanger.previous`. Fresh diagnostics classified both
  fixed-size Simulator device windows as automatically floating, restored them on-screen at their
  saved positions using successful position-only writes, and excluded them from the visible Tiled
  solve. Repeated workspace-1 switches solved exactly two managed windows and applied full-height
  frames across the complete display bounds to Claude and Chrome. The Simulator windows were parked
  again only after leaving their own workspace, which is the normal hidden-workspace path rather
  than the failed-resize state that caused this report.
- **User-confirmed live result (2026-08-24):** The maintainer confirmed that the installed candidate
  works well after switching through the affected workspaces: the fixed-size Simulator windows are
  available as floating surfaces and workspace 1 no longer retains their empty layout slots.
- **Live validation remaining:** Confirm the debug admission reason is
  `fixed-size-standard-window` and that a resizable Simulator window still participates normally
  before treating the broader admission regression as closed.

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
adding engineering tasks. `TODO.md` remains the feature index: detailed research may live in linked
design notes, but every active candidate must map back to a work item here or be labelled deferred.

### WR-007 — Pinned-display mode

- **Type:** Feature research
- **Status:** Needs decision
- **Source:** `docs/future-workspace-systems-decisions.md`
- **Decision:** Profile-owned versus local pinning, staged-display cardinality, workspace-home
  semantics, Full-mode interaction, and whether all-pinned is valid.

### WR-008 — Named whole-desk arrangements

- **Type:** Feature research
- **Status:** Needs decision
- **Sources:** `docs/future-workspace-systems-decisions.md` and
  `docs/omarchy-inspired-ideas.md`
- **Decision:** Launch behavior, same-app window matching, ownership/sync, captured data, unmatched
  windows, and merge versus replace semantics. Treat temporary window groups as the first
  session-only stage of this model; restoration preview, unmatched-window reporting, and bounded
  Undo are safety requirements rather than separate feature systems.

### WR-009 — Optional workspace/stage overview

- **Type:** Feature research
- **Status:** Needs decision
- **Source:** `docs/future-workspace-systems-decisions.md`
- **Decision:** Whether metadata-only is valuable first; whether thumbnails justify Screen
  Recording permission; placeholder/cache privacy; panel scope; click and drag semantics.

### WR-010 — Reusable layout presets

- **Type:** Feature research
- **Status:** Needs decision
- **Sources:** `docs/future-workspace-systems-decisions.md` and
  `docs/omarchy-inspired-ideas.md`
- **Decision:** Global/profile/workspace ownership, initial presets and participant policy,
  Tiled-only versus Freeform, and what topology can persist without guessing window identity.
  Resolve Omarchy-inspired workspace personalities through the existing per-workspace layout model:
  Grid/Columns are candidate Tiled presets, while Focus, Presentation, and Transient need explicit
  behavior and lifecycle boundaries rather than a parallel workspace-mode system.

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
  provenance, protected integration/stable branches and protected release tags. Sparkle 2.8.1 is
  integrated behind a hard Dev-build exclusion with local Stable/Beta selection, manual and opt-in
  automatic checks, an append-only build-number ledger, signed-archive appcast tooling, guarded
  initial-feed/monotonic-feed preflight, central allocation recheck, atomic feed staging, and
  deterministic two-release/stale-publication/runtime tests (691-test full suite and universal app
  build on 23 August 2026).
- **Remaining scope:** Back up the release EdDSA key through the maintainer's secure credential
  process, create and host the first appcast, validate older-to-newer packaged updates plus
  cancellation/failure/Beta-to-Stable/rollback behavior, then decide when automatic checking can
  default on. Accessibility migration guidance, Homebrew Stable distribution, and update/rollback
  failure handling also remain.
- **Gate:** Each later release still requires explicit maintainer approval.

## Done

### WR-082 — Publish WindowRanger 0.1.0 Beta 8

- **Result:** Published
  [`v0.1.0-beta.8`](https://github.com/AppRanger/windowranger/releases/tag/v0.1.0-beta.8) as a
  GitHub prerelease on 24 August 2026. The protected annotated tag points to exact release commit
  `25b8adf4e74ae69c6d5806130db9dccc55545061`; central `develop` owns build `9`, and the
  [release-branch CI run](https://github.com/AppRanger/windowranger/actions/runs/32775606443) passed
  723 tests, static analysis, an unsigned universal Release build, and both DMG smoke layouts.
- **Distribution evidence:** Stable Xcode 26.6 reproduced the 723-test pass and static analysis,
  then built the Developer ID-signed universal `arm64`/`x86_64` archive. Apple accepted the app
  (`59191fd9-f67d-4afc-bd0e-9e3abd52cce1`) and DMG
  (`cac8f0e9-f6a5-45a1-b706-6f47b38dc67b`) notarizations with zero issues; both stapled artifacts
  passed validation and Gatekeeper. The five public assets round-tripped against commit, build,
  channel, provenance, and SHA-256 values `9d1dbceb5190a9cabbf6b17c7ad2c7788df5d29078cb7016634fe72096545273`
  (DMG) and `b8d8f91733daa9199cdb1bc948377146c83bfa48a750d672d3cd0e396a3ed3f3`
  (ZIP).
- **Installed validation:** The exact DMG hash was verified and installed in the persistent macOS
  UTM guest. Its `/Applications` copy reported build `9`, Beta channel, release commit, Developer ID
  Team `44NAD22AK6`, notarized Gatekeeper acceptance, and CDHash
  `fe970a016e82eec2b4c074198372ffaae3aa1c35`, matching the distribution build. Live checks passed
  layout-slot release, fixed-size-window floating, ordinary TextEdit tiling, native file-panel
  floating, hidden-app slot exclusion, App Shelf startup hiding with retained configuration, and
  DesktopRanger coexistence: tagged desktop/recovery/island surfaces remained ignored while an
  unmarked same-bundle window remained manageable. No current-build crash report appeared.
- **Validation boundary:** Nested UTM input did not transmit held modifier combinations reliably,
  so the installed Command Palette, Shortcut Guide, and Shelf presentation hotkeys retain automated
  rather than live shortcut evidence. The guest was reused and received the exact DMG through a
  narrow host share; this is not pristine browser-download, multi-display, or physical-Mac evidence.
  Appcast generation, website deployment, and packaged Beta 7-to-Beta 8 update testing remain held
  for their separately approved checkpoint.

### WR-073 — Publish WindowRanger 0.1.0 Beta 7 as the Sparkle upgrade baseline

- **Result:** Published
  [`v0.1.0-beta.7`](https://github.com/AppRanger/windowranger/releases/tag/v0.1.0-beta.7) as a
  GitHub prerelease on 23 August 2026. The protected annotated tag points to release commit
  `bc92df8c6c962b56fc337ff9dfd23d9230a72f60`, whose tree matches reviewed `develop` commit
  `d0781e5377d6621d6e5e46e715e9244ca157dbe2`. The
  [candidate CI run](https://github.com/AppRanger/windowranger/actions/runs/32649902913) passed before
  promotion, and stable Xcode 26.6 then passed the exact release tree's 691 tests, static analysis,
  signed universal archive, and release packaging.
- **Distribution evidence:** Developer ID build `8` uses bundle identifier
  `dev.appranger.WindowRanger`, Team ID `44NAD22AK6`, CDHash
  `11aa2f794c9c35a46556fbf98ae4b6495aef34af`, the Beta update channel, the HTTPS appcast URL, and
  the WindowRanger-specific Sparkle public key. App notarization
  `6a6fe56f-a5b2-4891-9681-ad0373655dcb` and DMG notarization
  `db061403-2c1e-4b4f-9a4a-2d3e98e0481a` were accepted with zero logged issues. Both staples,
  Gatekeeper assessments, strict signatures, embedded Sparkle framework, universal architecture,
  and DMG verification passed.
- **Public asset evidence:** The public DMG, ZIP, two checksum files, and provenance manifest were
  downloaded after publication and round-trip verified against the tag. The DMG SHA-256 is
  `051a1a63544076c12715400d6c17342ec314a3554ffa8c2faa4f759d6773a385`; the ZIP SHA-256 is
  `af17b58f9358e629892f8511dfe0e48650a02348d19f9d8a013c5de247b4ce6e`.
- **Live-validation boundary:** This release intentionally leaves `appcast.xml` absent. Maintainer
  installation from the public GitHub DMG is the older side of the first real updater test; the
  later signed Beta and feed publication remain separate work.

### WR-062 — Publish WindowRanger 0.1.0 Beta 6

- **Result:** Published
  [`v0.1.0-beta.6`](https://github.com/AppRanger/windowranger/releases/tag/v0.1.0-beta.6) as a
  GitHub prerelease on 20 August 2026. The protected annotated tag points to release commit
  `afd77ac5787d07b2bd1f2f82e169036987e2f3db`, whose tree matches reviewed `develop` commit
  `9c7fc39969ea36adac706a67efbc9760fa2b7e26`. The
  [release-branch CI run](https://github.com/AppRanger/windowranger/actions/runs/32419565061)
  passed 610 tests, static analysis, the unsigned universal Release build, both Stable and Beta DMG
  smoke layouts, and artifact upload.
- **Streamlined Beta evidence:** The accepted Quick App visibility, geometry, focus-border, launch,
  Settings resurfacing, Command Palette, Placement Halo, and Globe/Fn Placement Wheel behavior had
  already passed signed daily testing and maintainer acceptance. These changes altered no packaging,
  signing, entitlement, bundle identity, migration, updater, or minimum-system boundary, so the
  approved repeat-Beta path skipped only the redundant packaged-app replacement install. All source,
  toolchain, signing, notarization, packaging, provenance, public-asset, and website gates still ran.
- **Distribution evidence:** Stable Xcode 26.6 produced universal Developer ID build `7` with bundle
  identifier `dev.appranger.WindowRanger`, Team ID `44NAD22AK6`, and CDHash
  `7d6cbac0a4cb7b531b50caedc138d37da15ed87a`. App notarization
  `f10e472d-ec1e-423e-8b1e-cd643b0d7f5f` and DMG notarization
  `cdd92e28-18b6-4f07-a527-c494a4123c76` were accepted with zero logged issues. Both staples,
  Gatekeeper assessments, strict signatures, DMG verification, and packaged-app equality passed.
  The public DMG, ZIP, two checksum files, and provenance manifest were downloaded and round-trip
  verified before and after publication; the DMG SHA-256 is
  `5ef7030a010d0b14f6b06c4166ebd0cdbd860f660f08f34b1deb0378ea58c5c4` and the ZIP SHA-256 is
  `58be664a5e88ef743daa4e0f20303f460b73686805fb57ea6f02ffd810954aa1`.
- **Website evidence:** [Website PR #6](https://github.com/AppRanger/windowranger-site/pull/6)
  merged as `8f713b0680436b386df1686537aec59360c03c7f` and deployed as Cloudflare version
  `dc96c0c5-9a51-4ea2-9524-ba8ef758123c`; documentation-only
  [PR #7](https://github.com/AppRanger/windowranger-site/pull/7) recorded that deployment as
  `7265dfac946fcbddf6aaa6c8858c343de9a7bfe6`. Both `windowranger.com` and
  `www.windowranger.com` show Download Beta 6 and link to the published release. The old Command
  Wheel visual and copy were replaced by a released-source Command Palette with Placement Halo
  render. Desktop and mobile browser checks found no horizontal overflow and zero console errors or
  warnings; the public 1496-by-1128 tour asset loaded successfully.

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
