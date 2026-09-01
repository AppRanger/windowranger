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

### WR-109 — Keep the first status menu at its final anchored position

- **Type:** Menu-bar popup positioning bug
- **Priority:** P1
- **Status:** Done
- **Result:** The detached status menu now finishes structural updates before tracking, measures its
  completed item tree, and uses the clicked button for horizontal screen alignment plus the menu-bar
  window's lower edge and a five-point visual gap for vertical placement. The existing mouse-up
  deferral and post-popup Settings handoff remain unchanged.
- **Evidence:** All 46 focused Menu Bar Presentation tests and the adjacent 149 Settings, shortcut,
  and support-report tests pass. The complete quick integration gate passes all 863 non-hosted tests
  plus project generation, release-ledger, Sparkle/Homebrew workflow, shell-syntax, and isolation
  checks. Signed universal Debug candidate `ec1120a0ff12-dirty` passed strict signature and clean
  startup checks; after successive placement refinements, on 1 September 2026 the maintainer
  confirmed the menu no longer jumped and accepted the final five-point spacing.

### WR-108 — Render menu-bar labels with the attached status-item appearance at startup

- **Type:** Menu-bar appearance bug
- **Priority:** P1
- **Status:** Done
- **Result:** Each status item now observes attachment to its real menu-bar window and later
  effective-appearance changes, then coalesces a deferred raster refresh so adaptive label and
  symbol colours no longer remain black until the first workspace switch.
- **Evidence:** All 44 focused Menu Bar Presentation tests pass, covering attachment observation,
  refresh coalescing/cancellation, and Light/Dark rasterization. Signed universal Debug revision
  `f50fe060419c-dirty` passed strict signature and startup checks; on 1 September 2026 the maintainer
  confirmed its menu-bar fonts started in the correct colour before switching workspace. The
  integration quick gate passes all 861 non-hosted tests plus project generation, release-ledger,
  Sparkle/Homebrew workflow, shell-syntax, and test-isolation checks.

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

### WR-106 — Reconstruct Tiled preview geometry before its first visit

- **Type:** Workspace preview correctness bug
- **Priority:** P1
- **Status:** Live validation — calculated first-visit geometry and the bounded startup preparation
  are implemented and pass complete automated verification; signed restart testing remains.
- **User-observed:** After restarting WindowRanger, a workspace that has not yet been visited can
  show its applications at the wrong positions and sizes in the workspace preview. Switching to
  that workspace once immediately corrects the preview.
- **Expected:** An inactive workspace preview uses the layout geometry it would receive on first
  activation, without requiring the workspace to be visited.
- **Reproduced cause:** Inactive Accordion previews reconstruct deterministic geometry from tracked
  session metadata. Inactive Tiled previews use the last solved frame only when that workspace has
  already been laid out during the current process; after restart they otherwise fall back to each
  window's restore frame until the first activation populates the solver cache.
- **Smallest useful outcome:** Reconstruct inactive Tiled preview frames on demand from the saved BSP
  tree, window identities and weights, current display bounds, orientation, gaps, and padding. When
  captured thumbnails are already enabled and authorized at launch, first park inactive windows and
  then give eligible Tiled and Accordion participants their predicted size once while they remain
  parked, so applications render truthful pixels before first activation. Do not activate or focus
  the workspace, add a timer, perform another AX scan or capture, or retain a second layout cache.
- **Acceptance:** Before first activation, Tiled preview geometry matches the normal solver for the
  same tree and display configuration, and eligible inactive automatic-layout windows have that
  predicted size while remaining non-meaningfully-visible at the parking edge. The startup pass is
  disabled when thumbnail previews or authorization are unavailable; active, Freeform, floating,
  excluded, fixed-size, deferred, minimized, full-screen, and keep-on-all-workspaces windows are
  untouched. Focused preview tests and the complete non-hosted gate pass before a separately
  approved install; signed restart validation checks for flashes, rejected sizing, and exact pixels.
- **Implemented:** Inactive Tiled previews reconstruct their would-be activation frames from the
  existing saved BSP tree, ordered window identities and weights, current display bounds,
  orientation, gaps, and padding. When captured previews are enabled and Screen Recording is
  already authorized at launch, restoration parks inactive windows normally and then performs one
  bounded preparation pass. Eligible resizable Tiled and Accordion participants must already be
  non-meaningfully-visible; each retains its parked position while receiving its predicted size and
  is verified still parked afterwards, with one defensive re-park if macOS moved it into a visible
  area. Active, Freeform, floating, excluded, fixed-size, deferred, minimized, full-screen, and
  keep-on-all-workspaces windows are excluded. One of several light-hearted messages is shown through
  the existing nonactivating feedback overlay when work is actually required. The pass adds no
  capture, timer, polling, second layout cache, or ongoing CPU or memory cost.
- **Automated evidence (29 August 2026):** All 23 focused Workspace Preview tests pass, including
  exact equality between pre-visit preview reconstruction and the production Tiled solver for a
  saved nested tree on an external display with automatic orientation, asymmetric outer padding,
  and unequal inner gaps, plus the startup eligibility boundary and deterministic message rotation.
  The Debug app target builds successfully. The complete quick gate passes all 812 non-hosted tests
  plus project generation, release-ledger, Sparkle workflow, and test-isolation checks. Signed-app
  validation must still restart WindowRanger, watch for any visible flash or rejected resize, and
  inspect Tiled and Accordion workspaces before visiting them.
- **Earlier installed evidence (29 August 2026):** With explicit maintainer approval, signed universal
  Debug daily revision `7bcdbefd1d75-dirty` was installed and relaunched from
  `/Applications/WindowRanger.app` as process `34882`. Strict deep signature verification passed
  under Team `44NAD22AK6`; the executable contains `x86_64 arm64`, has CDHash
  `a6fc08ee17d84cb050e9d81c08cc69b5c7aa7e5e`, and the installed Debug library matches the
  just-built library byte for byte. Fresh diagnostics session
  `5AD28AC8-1DFB-49B1-893A-9040973BA718` reached `startup-state-ready`.
- **Live finding (29 August 2026):** Before workspace 1's first visit, its calculated preview
  positions and 50/50 full-height Tiled frames were correct, and the current session contained zero
  layout solves for that workspace. Read-only Window Server evidence showed its parked Claude source
  at `1200x800` while Chrome was already `1913x1582`. The capturer sizes both output buffers from
  the predicted descriptor frame while asking ScreenCaptureKit to preserve the current source aspect
  ratio. Chrome therefore fills its preview, while Claude leaves transparent pixels that reveal a
  wallpaper strip and make it appear too short.
- **Approved follow-up (29 August 2026):** The maintainer chose truthful application rendering over
  cropping, stretching, or fitting stale restore-size pixels. The bounded startup pass must park
  first, resize only eligible inactive automatic-layout windows in place, and show one rotating
  light-hearted preparation message while it runs. This intentionally changes the earlier
  no-window-write preview boundary, but only when captured thumbnails are enabled and authorized.
- **Current installed candidate (29 August 2026):** With explicit maintainer approval, signed
  universal Debug daily revision `7bcdbefd1d75-dirty` was installed and relaunched from
  `/Applications/WindowRanger.app` as process `52300`; the prior daily remains recoverable at
  `/Applications/.WindowRanger.previous`. Strict deep signature verification passed under Team
  `44NAD22AK6`, the app contains `x86_64 arm64`, has CDHash
  `1650d389fbfea4dc3ceea02956b36ac85635cea1`, and its Debug library matches the just-built library
  byte for byte. Fresh diagnostics session `D9CDD757-8004-467B-B6FE-2D5FE8D5816E` reached
  `startup-state-ready`, prepared four parked windows with four successful frame writes, settled all
  four at their target sizes, required zero defensive re-parks, and recorded no error or fault. A
  visual check of an unvisited Accordion workspace remains before acceptance. The maintainer
  inspected the original unvisited Tiled workspace before activating it and confirmed its prepared
  first-visit preview was correct.

### WR-105 — Make workspace layout choices visually self-explanatory

- **Type:** Workspace Settings visual refinement
- **Priority:** P2
- **Status:** Live validation — implemented, visually inspected, and complete non-hosted verification
  passes; signed installed-app interaction remains.
- **Requested:** 29 August 2026.
- **Smallest useful outcome:** Replace the text-only Layout Style and Orientation segmented controls
  with compact visual choices. Freeform, Tiled, and Accordion must depict their actual window
  relationship; Automatic, Horizontal, and Vertical must show the direction the selected automatic
  layout will use rather than relying on its name alone.
- **Functionality boundary:** This is presentation only. Preserve the existing workspace layout and
  orientation values, profile ownership, persistence, layout reconciliation, Copy Layout, legacy
  geometry migration, Undo behavior, conditional geometry controls, and inactive-profile isolation.
- **Acceptance:** Every choice remains clearly named, keyboard reachable, and VoiceOver-labelled;
  the selected state remains unambiguous in Light and Dark appearance; diagrams truthfully show
  left-to-right versus top-to-bottom flow and Accordion overlap; the production Workspaces screen
  remains usable at its minimum supported width; focused Settings tests and the complete non-hosted
  gate pass before a separately approved signed daily install.
- **Implemented:** Layout Style and Orientation now use one reusable labelled visual-choice card.
  Freeform shows independently overlapping windows, Tiled shows non-overlapping panes, and
  Accordion shows an overlapping stack with visible neighbouring edges. Horizontal and Vertical
  use the selected layout's actual left-to-right or top-to-bottom geometry; Automatic pairs a wide
  horizontal result with a portrait vertical result. Selection has a native accent outline, tint,
  and checkmark, while every button retains a plain-language VoiceOver label, selected value, and
  explanatory hint. No model, persistence, or layout-engine path changed.
- **Automated and visual evidence (29 August 2026):** All 136 focused Radial Menu and Settings tests
  pass, including deterministic wording for the actual window relationships. The complete quick
  gate passes all 809 non-hosted tests plus project generation, release-ledger, Sparkle workflow,
  and test-isolation checks. The production Workspaces hierarchy rendered offscreen in Light/Dark,
  Tiled/Accordion, wide/minimum-width compact, long-name, conflict, and many-workspace fixtures.
  Inspection found all diagrams and labels legible, distinct selected state without colour alone,
  and no truncation or horizontal overflow. Pointer selection, keyboard traversal, and VoiceOver
  announcement remain signed installed-app validation.
- **Installed candidate (29 August 2026):** With explicit maintainer approval, signed universal
  Debug daily revision `7bcdbefd1d75-dirty` was installed and relaunched from
  `/Applications/WindowRanger.app` as process `29087`. Strict deep signature verification passed
  under Team `44NAD22AK6`; the executable contains `x86_64 arm64`, has CDHash
  `f7611f1bec69c640c363d8ea278fda4a53f4f8bf`, and matches the just-built executable and Debug
  library byte for byte. Fresh diagnostics session `FB539292-7267-46EB-8564-BE1DB28E6251`
  reached `startup-state-ready` without a recorded error, fault, or timeout. The previous daily
  remains recoverable at `/Applications/.WindowRanger.previous`. The maintainer subsequently
  confirmed the visual selectors look good in the installed app; keyboard traversal and VoiceOver
  announcement remain the outstanding acceptance boundary.

### WR-104 — Use one menu-bar composition on every supported macOS release

- **Type:** Menu-bar consistency and code simplification
- **Priority:** P1
- **Status:** Live validation — implementation, complete automation, and the macOS 26 one-display
  compatibility pass are complete; an exact release-signed physical-Mac check remains.
- **Evidence:** User-observed on 29 August 2026 after installing Beta 9 on a macOS 26 Mac. Full mode
  used the retained pre-27 custom strip, including a redundant app glyph and visibly heavier
  workspace capsules, while the newer Mac used the grouped standard-status-item presentation.
- **Expected behavior:** Compact, Medium, and Full have the same display-group composition and
  interaction model on every supported macOS release; operating-system material and tint may still
  differ naturally.
- **Smallest useful outcome:** Make the standard per-display-group status items the sole production
  path without raising WindowRanger's minimum macOS version. Remove the superseded single custom
  host, its standalone app glyph, native child workspace buttons, version switch, and obsolete
  tests and documentation.
- **Acceptance:** Focused menu-bar and complete non-hosted gates pass. A signed candidate is installed
  in the persistent macOS 26 UTM guest and visibly checked in Compact, Medium, and Full. Full must
  switch explicit workspaces, open the menu from non-workspace/secondary/Control-click actions,
  preserve hover previews, and retain coherent ordering and press feedback. Automated, guest
  installation, and observed GUI evidence remain separate.
- **Implemented:** Every supported macOS release now uses one standard status item per logical
  display group and the same rendered hit-target geometry. The superseded custom status host,
  standalone app glyph, native child buttons, operating-system composition switch, compatibility
  preview, and their obsolete tests were removed. The Settings preview now always represents the
  production grouped composition.
- **Automated evidence (29 August 2026):** The focused 41-test menu-bar presentation suite and two
  visual snapshot tests passed. `./scripts/verify-local-ci.sh --quick` passed all 808 non-hosted
  tests plus the release-build registry, Sparkle workflow, project-generation, and test-isolation
  checks. The final universal Debug app built successfully for macOS 14+ with no new compiler
  warning, passed strict deep signature verification, and embedded source revision
  `e9358197fdcb-dirty`.
- **macOS 26 guest evidence (29 August 2026):** The persistent UTM guest was visibly identified as
  UUID `74D1CCD5-8C65-45B0-8D4C-4B22A24E9191`, macOS 26.6.2 build 25G83, arm64. The exact source
  candidate replaced Beta 9 recoverably. Its host Apple Development profile was correctly rejected
  because that profile does not include the VM, so the same guest test bundle was re-signed ad hoc
  after removing the machine-specific profile; version 0.1.0, build 1, bundle identifier, and source
  revision remained verified. With Accessibility granted, Compact, Medium, and Full each rendered
  visibly through the grouped status item. Full visibly switched 1 → 2 → 3 with the selected segment
  updating, opened the application menu from a secondary click, and presented the hover shelf using
  its no-app fallback. Diagnostics then recorded real AX candidates and a verified Finder focus
  restoration while switching 3 → 2 → 1 → 3.
- **Remaining live boundary:** The guest proves the macOS 26 grouped composition and one-display
  interaction path, not Developer ID/release packaging, multi-display ordering, or a physical Mac.
  UTM's nested input did not give a reliable held-Control-click or final display-icon primary-click
  observation; those routes retain focused automated coverage. Screen Recording remained off, so
  the hover check exercised the icon/fallback shelf rather than captured window thumbnails.

### WR-102 — Keep newly added workspace shortcuts live without relaunching

- **Type:** Global shortcut registration bug
- **Priority:** P1
- **Status:** Live validation — diagnostic-supported hardening is implemented and focused automated
  verification passes; the exact original Carbon delivery failure was repaired by restart but could
  not be deterministically isolated from the old diagnostics.
- **User-observed:** On a new Mac, the four initial workspace switch and move shortcuts worked, but
  the shortcut pair for a newly added fifth workspace did nothing until WindowRanger was restarted.
- **Expected:** Adding, removing, renaming, reordering, or rekeying a workspace updates its global
  switch and move shortcuts immediately, without disrupting unchanged shortcuts or requiring a
  relaunch.
- **Diagnostic support:** The affected session repeatedly completed five-workspace profile
  transitions and the Shortcut Guide exposed five valid, conflict-free Navigate actions. The first
  four shortcuts continued to dispatch, while the reported fifth action produced no recorded Carbon
  event. After a clean restart, the added workspace UUID dispatched successfully. Pause, shortcut
  recording, fullscreen/game scope, invalid keys, conflicts, and logged Carbon registration or
  unregistration failures do not fit the captured session. The prior diagnostics did not record
  successful registration snapshots, so the failed internal step remains unproven.
- **Implemented:** Hot-key refreshes now reconcile the desired owner/chord set instead of tearing
  down every working Carbon registration. An unchanged binding retains its known-good token; adding
  one workspace registers only its switch and move bindings. Runtime callers pass the exact emitted
  workspace snapshot, and privacy-safe completion diagnostics record the trigger, scope, workspace
  IDs, eligible/registered counts and owners, issue counts, plus deferred shortcut-recording refreshes.
- **Automated evidence:** The focused Hot Key and Settings suite proves a four-to-five workspace
  update preserves every existing token, adds exactly two registrations, exposes both new owners,
  retries isolated failures without replacing working bindings, safely retries failed removals, and
  records the completed snapshot without workspace names. The combined 216 focused shortcut,
  Settings, onboarding, permission and colour tests pass. The complete non-hosted suite passes all
  814 tests; test isolation, Release static analysis, the unsigned universal Release app build, both
  unsigned Stable/Beta DMG smoke packages, and whitespace verification also pass.
- **Review evidence:** Skeptical read-only review found no P0-P2 correctness or regression issue in
  the registration reconciliation, exact AppDelegate snapshot wiring, onboarding window/permission
  behavior, or colour migration. Its independent focused run passed all 170 selected tests.
- **Live boundary:** In the signed candidate, add a fifth workspace, immediately switch to it and
  move a focused window to it, then change its key and repeat without relaunching. Also confirm the
  first four shortcuts remain responsive throughout. If it fails, capture the new
  `registration-completed` record before restarting.

### WR-101 — Prevent a new Mac from replacing existing iCloud settings with defaults

- **Type:** Data-loss sync bug and recovery
- **Priority:** P0
- **Status:** Live validation — local recovery completed and independently verified with sync off;
  the pull-first write barrier and explicit replacement path are implemented, fully verified, and
  installed as a signed daily build, and verified against the recovered local data after launch.
  Live recovery publication remains.
- **Observed:** On a newly installed Mac, enabling **Sync settings with iCloud** replaced the existing
  custom cloud profile library with the new installation's defaults. This Mac then received that
  valid default library and replaced its local custom configuration. Both Macs now show the same
  default setup.
- **Expected:** Joining iCloud from a new Mac must first use an existing valid cloud library and must
  never publish a fresh/default local library over it. Replacing iCloud with this Mac must be a
  separate explicit action with clear consequences.
- **Reproduction and cause:** `SettingsStore.iCloudSyncEnabled.didSet` calls `pushToICloud()` as soon
  as the switch becomes true, before any cloud pull. The onboarding switch uses the same setter. The
  existing `testReenablingPushesLocalSettingsWithoutDeletingExistingCloudData` codifies this unsafe
  direction. A later pull then correctly treats the newly uploaded default library as authoritative.
- **Recovery evidence:** The live preference domain contains a 2,452-byte `Default` profile library
  with five workspaces and no app rules. The 08:37 Time Machine backup contains the pre-incident
  9,394-byte library: `Desktop 2 screens` and `Laptop`, nine workspaces each, 14 and 3 app rules, and
  the configured Quick Apps. Its 2,759-byte Mac-local state is also present. Do not restore while
  either Mac can continue syncing. Preserve the backed-up preference file and verify decoded profile
  names before any replacement.
- **Recovery result:** With both installations closed, preserved the damaged live preferences and
  the 08:37 Time Machine source separately, restored a third working copy with iCloud sync forced
  off, and read the live preference domain back through macOS. It contains `Desktop 2 screens` and
  `Laptop`, nine named workspaces each, 14 and 3 app rules, the configured Quick Apps, and the prior
  `key` menu-bar label mode. WindowRanger remained closed throughout the restore.
- **Implemented:** Enabling sync now synchronizes and performs a read-only pull. Every profile and
  supported global-setting cloud writer is blocked until a valid remote library arrives; absent
  data remains waiting for delayed delivery and rejected data remains blocked. Settings and
  onboarding expose the waiting state and a separately confirmed complete replacement action. That
  action can publish a verified local library while ordinary sync is still off, which preserves a
  recovery source before replacing known-bad but valid cloud content. The confirmation states that
  this also enables ongoing sync, and an invalid local library now produces a visible issue without
  enabling sync or writing anything.
- **Focused evidence:** 21 iCloud tests cover local-only startup, saved enablement, valid remote
  precedence with zero writes, delayed arrival, edits while waiting, rejected data, oversized local
  data, explicit empty-cloud initialization, and recovery replacement before any pull. The related
  Menu Bar and Settings tests also pass.
- **Complete automated evidence:** The complete isolated non-hosted suite passes all 809 tests, test
  isolation passes, Debug static analysis passes, and the working tree has no whitespace errors.
- **Review evidence:** Skeptical review found no ordinary P0/P1 data-loss path. Its two P2 recovery
  UI findings—the silent invalid-local failure and undisclosed sync enablement—were corrected and
  the 21-test iCloud suite rerun successfully. Real iCloud delayed-delivery behavior remains a signed
  live-validation boundary.
- **Installed evidence:** Signed universal Debug daily build `539e0bf945e9-dirty` was installed and
  launched from `/Applications/WindowRanger.app`. Strict code-sign verification passed. The live
  domain still has iCloud sync off and retains `Desktop 2 screens` with 9 workspaces, 14 app rules,
  and 2 Quick Apps plus `Laptop` with 9 workspaces and 3 app rules.
- **Acceptance:** First enable from Settings and onboarding never writes before resolving an existing
  cloud library; a valid existing remote wins without any local write; replacing cloud content is an
  explicit confirmed action; an actually empty cloud store has a safe, deliberate initialization
  path; disabling remains local-only and non-destructive. Cover delayed cloud availability, valid and
  rejected remote data, defaults versus customised local data, both enablement surfaces, and recovery.

### WR-097 — Remove the focused application from Applications via Command Palette

- **Type:** Command Palette and application-configuration improvement
- **Priority:** P2
- **Status:** Live validation — implemented, documented, reviewed, focused and complete automated
  verification passed, unsigned universal build passed, and signed daily build installed;
  maintainer acceptance remains.
- **Requested:** 28 August 2026 after confirming WR-080 already adds the focused application to
  the active profile's Applications list.
- **Smallest useful outcome:** When the Command Palette was captured from a regular external app
  that already has an Application Rule in the active profile, offer **Remove <App> from
  Applications**. Removing deletes that profile rule only; it does not quit the app or close its
  windows, and the engine resumes its normal no-rule behavior for those windows.
- **Discoverability:** Index the removal action under both `remove` and `add`, as well as current-app,
  application, settings, and rule terms. A user who searches for Add because they do not know the
  app is already configured therefore sees the truthful inverse action with an **Already in
  Applications** explanation rather than an empty result.
- **Safety boundary:** Capture the app's bundle identity, active profile, and exact `.appRule`
  membership in the palette command. The MainActor mutation must fail closed if the active profile
  or mutually exclusive Application/Shelf membership changes before dispatch. Removing a Quick App
  or a rule from a profile merely being edited in Settings is out of scope.
- **Functionality boundary:** Preserve WR-080's existing Add/Move entries, Shelf capacity and
  exclusivity behavior, focused-app eligibility, current-workspace capture, command dismissal, and
  engine App Rule reconciliation. Do not infer app-wide rules from one window's floating or layout
  override.
- **Acceptance:** Focused index tests prove the Remove entry appears only for `.appRule`, typing
  `remove` or `add` finds it, and existing Add/Move alternatives remain correct. Dispatcher and
  SettingsStore tests prove exact routing, active-profile ownership, intended removal, and rejection
  after profile or membership changes. Run the focused suites, complete non-hosted verification,
  skeptical review, unsigned universal build, then a separately approved signed daily install and
  live Command Palette removal check.
- **Implemented:** The palette now emits one typed removal command only for captured `.appRule`
  membership. The command carries the bundle identifier, active profile, and expected membership
  through the shared dispatcher to a MainActor SettingsStore guard, then removes only the active
  profile's rule. Removing an assignment-only rule leaves existing windows in their current
  workspace; future/reset/reopened windows no longer inherit that pin. Removing Keep on all,
  layout exclusion, or secondary-window floating resumes ordinary engine policy immediately and
  may therefore park or relayout affected windows as the existing Settings removal path already
  does. `add`, `remove`, and `delete` all find the explicitly titled removal entry.
- **Automated evidence:** All 57 focused Command Palette and Quick App/Application configuration
  tests pass. The complete non-hosted suite passes 766/766, repository quick verification passes,
  and the unsigned Debug app builds with both `arm64` and `x86_64` architectures. Coverage includes
  entry visibility, inverse `add` alias discovery, dispatcher arguments, successful removal, stale
  profile rejection, wrong/no-rule membership rejection, and Quick App preservation.
- **Review evidence:** Skeptical review found no blocking correctness or safety issue. It confirmed
  exhaustive command routing, duplicate stale-context guards, active-versus-editing profile
  ownership, App Rule/Shelf exclusivity, and existing engine reconciliation after removal.
- **Install evidence:** Signed universal Debug candidate `a249b813213a-dirty` was installed and
  relaunched from `/Applications/WindowRanger.app` as PID `72409` on 28 August 2026. Strict deep
  signature verification passed under Team `44NAD22AK6`, the executable contains `arm64` and
  `x86_64`, its CDHash is `57cb96411b78fc5f7fdbcaf4b5e2a9bfa7266aec`, and diagnostics session
  `848371A5-6D41-4B69-A5EA-D2E0FBAF0B75` reached startup ready without an observed failure, error,
  or timeout. The previous clean daily build remains recoverable at
  `/Applications/.WindowRanger.previous`.

### WR-098 — Choose where Command Palette opens

- **Type:** Command Palette presentation preference
- **Priority:** P2
- **Status:** Done — implemented, documented, reviewed, automated-test verified, signed daily build
  installed, and maintainer live acceptance recorded on 28 August 2026.
- **Requested:** 28 August 2026.
- **Current behavior:** The palette always opens near the top centre of the captured interaction
  display, 84 points below its usable top edge. The choice is not configurable or persisted.
- **Recommended smallest useful outcome:** Add a Mac-local **Position** preference with **Top**,
  **Centre**, and **Bottom** choices. Keep **Top** as the migration-safe default, continue following
  the captured interaction display, and keep every base and expanded palette frame inside that
  display's usable area.
- **Functionality boundary:** Change presentation geometry only. Do not change command contents,
  search or keyboard behavior, external-focus capture, target display selection, Placement Halo
  behavior, profiles, or iCloud content. The setting belongs to this Mac because it describes local
  display geometry.
- **Decision:** The maintainer approved the three vertical positions on 28 August 2026. A future
  nine-position grid remains separate because the halo currently grows 200 points to the right;
  right-edge positions cannot remain truthful without shifting or mirroring that expansion.
- **Acceptance:** Geometry tests cover every choice, negative-coordinate displays, usable-area
  margins, undersized displays, and opening/closing the expanded Placement Halo without drift.
  Settings persistence remains local and survives relaunch. Focused Command Palette and Settings
  tests, the complete non-hosted suite, an unsigned universal build, and a separately approved
  signed daily install and live multi-display check are required.
- **Implemented:** Command Palette Settings now offers Top, Centre, and Bottom. Top preserves the
  original 84-point inset. A pure geometry policy places the base palette on the captured
  interaction display, retains its horizontal position while the right-side Halo fits, shifts only
  enough to contain an overflowing Halo, and recomputes the exact base frame on collapse. The
  preference is stored only in this Mac's local defaults and is absent from profiles and iCloud.
- **Automated evidence:** All 154 focused Command Palette and Settings tests pass. The complete
  repository quick gate passes 773/773 with non-hosted isolation intact, `git diff --check` passes,
  and the unsigned Debug app builds successfully as a universal `arm64` and `x86_64` binary.
  Coverage includes all three positions, the migration-safe default, negative-coordinate and
  undersized usable frames, stationary ordinary Halo expansion, minimum overflow correction,
  collapse without drift, local persistence, relaunch, iCloud exclusion, and Settings search.
- **Review evidence:** Skeptical review found no blocking correctness, persistence, geometry, UI,
  or documentation issue. The remaining non-blocking test boundary is controller-level AppKit
  presentation, whose screen lookup is not injected; pure geometry, provider wiring, compilation,
  and the universal build are covered, while signed live use remains required.
- **Install evidence:** With explicit approval, signed universal Debug candidate
  `cce1c8e663e3-dirty` was installed and relaunched from `/Applications/WindowRanger.app` as PID
  `87361` on 28 August 2026. Strict deep signature verification passed under Team `44NAD22AK6`, the
  executable contains `arm64` and `x86_64`, and its CDHash is
  `cf69542cc7ee6933903a0aa5b62449d5828d91b8`. Fresh diagnostics session
  `BCC5A5C3-1E4E-44EC-BEFA-F3CC53BAF817` reached startup ready without an observed error, fault, or
  timeout. The previous daily build remains recoverable at `/Applications/.WindowRanger.previous`.
- **Live evidence:** On 28 August 2026, the maintainer confirmed the installed Top, Centre, and
  Bottom choices were all working, including the requested Command Palette positioning behavior.

### WR-099 — Make Tiled gaps and padding visual and intuitive

- **Type:** Workspace Settings interaction and visual improvement
- **Priority:** P2
- **Status:** Live validation — third link-alignment correction implemented, documented,
  automated-test/native-visual verified, installed, and accepted; the broader interaction and
  accessibility matrix remains.
- **Requested:** 28 August 2026.
- **Previous behavior:** Tiled workspaces exposed two Inner gaps and four Outer screen padding values
  as six plain Stepper rows. The values are precise but their spatial meaning is not visible.
- **Selected direction:** Keep the existing native macOS Workspaces inspector and replace only those
  rows with two lightweight visual editors. Inner gaps uses a small tiled preview beside Horizontal
  and Vertical controls; Outer padding uses an inset-screen preview beside Top, Right, Bottom, and
  Left controls. Each group also offers an optional local editing link so related values can be kept
  equal without adding profile state.
- **Functionality boundary:** Preserve `WorkspaceLayoutGaps`, its existing ranges, per-workspace
  persistence, Undo behavior, layout reconciliation, Copy Layout, legacy geometry migration, and
  Freeform/Accordion control visibility. Linking is transient Settings UI state and must never be
  serialized or silently affect another workspace.
- **Acceptance:** The diagrams truthfully distinguish inner horizontal/vertical spacing from outer
  top/right/bottom/left padding; every exact value remains visible and keyboard/VoiceOver operable;
  linked edits update only the intended group and reset safely when workspace context changes; and
  compact Settings widths remain usable. Add deterministic edit-policy and Settings tests, render
  the native production view against the selected visual direction, run the complete non-hosted
  gate and unsigned universal build, obtain skeptical review, then use a separately approved signed
  daily install for maintainer acceptance.
- **Implemented:** Tiled Workspaces now use a neutral four-pane diagram with accent-coloured inner
  gap channels and an inset-screen diagram whose accent band maps outer padding. Native Steppers
  retain lossless point readouts and their adjustable accessibility role. Wide Settings arranges the
  four outer values as a physical 2-by-2 edge map; compact Settings stacks the same controls. Keep equal
  and Keep all sides equal are transient inspector links: activation normalizes the current group,
  linked edits update only that group and participate in native Undo, and both links reset when the
  workspace, profile, or layout context changes. Untouched legacy geometry remains nil until a real
  value edit or the existing explicit defaults action.
- **Automated evidence:** All 130 focused Settings tests pass. The complete repository quick gate
  passes 779/779 with the non-hosted boundary intact; `git diff --check` passes; and the unsigned
  Debug app builds as a universal `x86_64 arm64` binary. Coverage includes group normalization,
  linked edit isolation, legacy migration preservation, lossless fractional readouts, native Undo,
  reset state, and layout-specific control visibility.
- **Visual evidence:** The production Settings hierarchy renders offscreen without launching or
  installing WindowRanger. Wide Light/Dark, minimum-width compact, asymmetric-direction, and all-zero
  fixtures were inspected against selected direction 2. Accent colour describes only actual gaps or
  padding; 0 pt renders as a neutral separator rather than a non-zero blue band; no clipping or
  wrapping remains in the tested states.
- **Review evidence:** Skeptical rereview found no remaining P0-P2 issue after the legacy migration,
  fractional readout, zero-gap truthfulness, native Stepper accessibility, and linked-edit Undo
  fixes. Live VoiceOver behavior remains a manual signed-app boundary.
- **Install evidence:** On 28 August 2026, signed universal Debug daily revision
  `96f82764b787-dirty` was installed and relaunched as PID `6022` from
  `/Applications/WindowRanger.app`. Strict deep signature verification passed under Team
  `44NAD22AK6`; the executable contains `x86_64 arm64` and has CDHash
  `e80a3e5afc14774885097dca8f8962c0b744d13e`. Fresh diagnostics session
  `A9B32F87-F93A-4B42-902F-62AA8E745B30` reached `startup-state-ready` without an error, fault,
  timeout, or failed event. The previous daily build remains recoverable at
  `/Applications/.WindowRanger.previous`.
- **User-observed follow-up:** In the installed candidate on 28 August 2026, the maintainer found
  that 5 pt gaps and padding were technically drawn but remained too faint to read in the compact
  diagrams until roughly 30 pt, and that the Inner Keep equal row looked misaligned because its
  label and switch stretched across the whole controls column.
- **Correction evidence:** The diagrams now use a square-root visual scale that preserves exact
  zero, monotonic growth, and the maximum while making a 5 pt value several screen pixels wide.
  This changes only the explanatory preview, not stored values or live layout geometry. The Inner
  Keep equal label and switch were first grouped together at the trailing edge. All 131 focused
  Settings tests and all 780 tests in the complete repository quick gate passed, including
  deterministic small-value preview coverage. The production offscreen Light and Dark fixtures at
  5 pt on every edge were inspected with both diagrams legible. `git diff --check` passed.
- **Corrected install evidence:** On 28 August 2026, the refreshed signed universal Debug daily
  revision `96f82764b787-dirty` was installed and relaunched as PID `13708` from
  `/Applications/WindowRanger.app`. Strict deep signature verification passed under Team
  `44NAD22AK6`; the executable contains `x86_64 arm64` and has CDHash
  `149da37c67d45c0b9b971a916a65435059f6e02f`. Fresh diagnostics session
  `83B30CC5-316F-4254-A595-AEA151649653` reached `startup-state-ready` without an error, fault,
  timeout, or failed event. The superseded candidate remains recoverable at
  `/Applications/.WindowRanger.previous`.
- **Second user-observed follow-up:** The maintainer accepted the corrected previews but confirmed
  that Inner Keep equal still looked misaligned in the installed build: grouping the contents did
  not fix its placement because the toggle remained a third row beneath the two values.
- **Second correction:** In wide Settings, Inner Keep equal became a separate right-hand column
  beside the Horizontal and Vertical values. A flexible spacer gave its switch the same far-right
  edge as Outer Keep all sides equal while keeping the label on one line. Compact Settings kept the
  control in a trailing stacked row. The production wide Light/Dark and minimum-width compact
  fixtures were inspected, the isolated render passed, the complete repository quick gate passed
  all 780 tests, and `git diff --check` passed.
- **Final alignment install evidence:** On 28 August 2026, the refreshed signed universal Debug
  daily revision `96f82764b787-dirty` was installed and relaunched as PID `17783` from
  `/Applications/WindowRanger.app`. Strict deep signature verification passed under Team
  `44NAD22AK6`; the executable contains `x86_64 arm64` and has CDHash
  `3d903e04b37bda557fbe417f831f9ffda77b1bad`. Fresh diagnostics session
  `0774482F-AE57-4E9E-9B34-5E1191C4568F` reached `startup-state-ready` without an error, fault,
  timeout, or failed event. The preceding corrected candidate remains recoverable at
  `/Applications/.WindowRanger.previous`.
- **Third user-observed follow-up:** The separate right-hand column improved the installed layout,
  but the maintainer confirmed that its label remained right-grouped beside the switch rather than
  beginning where the Outer Keep all sides equal label begins.
- **Third correction:** Inner Keep equal now uses the same visible row geometry as the Outer link:
  its label begins immediately after the value column, flexible space separates it from the switch,
  and the switch remains on the shared far-right edge. The responsive candidate retains a compact
  intrinsic width so the normal-width inspector stays side-by-side instead of falling back to its
  stacked layout prematurely. The production extra-wide and minimum-width compact fixtures were
  inspected; both layouts are clean and the two wide link labels and switches align. The visual
  fixture now includes the extra-wide state that exposed this distinction. The isolated production
  render and complete repository quick gate pass all 780 tests, and `git diff --check` passes.
- **Third correction install evidence:** On 28 August 2026, the refreshed signed universal Debug
  daily revision `96f82764b787-dirty` was installed and relaunched as PID `24616` from
  `/Applications/WindowRanger.app`. Strict deep signature verification passed under Team
  `44NAD22AK6`; the executable contains `x86_64 arm64` and has CDHash
  `3aefb6faf2f89f47eea7af4c02f0582eff1e27df`. Fresh diagnostics session
  `E545E9E2-BED1-48AF-AE12-51D30E7DBF8C` reached `startup-state-ready` without an error, fault,
  timeout, or failed event. The preceding alignment candidate remains recoverable at
  `/Applications/.WindowRanger.previous`.
- **Live alignment evidence:** On 28 August 2026, the maintainer accepted the installed final link
  alignment as the checkpoint before a potentially reversible follow-up experiment and requested
  that WR-099 be committed.
- **Live validation remaining:** Complete the wider immediate-layout, both-link, Undo,
  workspace/profile reset, compact resizing,
  keyboard-adjustment, and VoiceOver checks.

### WR-100 — Add reusable interactive workspace previews

- **Type:** Feature and privacy-sensitive presentation infrastructure
- **Priority:** P2
- **Status:** Live validation — implemented, skeptically reviewed, visual-fixture checked, all 806
  non-hosted tests passed, static analysis passed, and the unsigned universal Debug app built on
  28 August 2026. The signed daily Debug build including the home-display aspect-ratio refinement
  was installed on 29 August 2026. The subsequent per-window capture-aspect fix is automated-test
  verified and installed for live validation. The subsequent Settings initial-fill fix is also
  automated-test verified and installed for live validation. The wallpaper refinement is implemented
  and has passed its focused and complete non-hosted suites plus Debug static analysis. Its signed
  daily Debug build was installed on 29 August 2026; the manual matrix below remains unverified.
- **Requested:** Add one reusable workspace-preview component that can present a workspace as a
  scaled desktop, optionally enrich eligible managed windows with ScreenCaptureKit thumbnails, and
  support whole-workspace activation, independent item activation, or both interaction modes.
- **Selected direction:** Keep the permission-free metadata preview as the universal fallback. Add
  a separate Mac-local, off-by-default **Show window previews** setting for captured pixels. Request
  Screen Recording access only from that explicit Settings action; never request it at startup,
  merely by opening Settings or the menu-bar shelf, or from tests. Use bounded one-shot captures and
  a shared in-memory cache rather than a stream or polling loop.
- **First integration boundary:** Reuse the same component in Workspace Settings tabs and the Full
  menu-bar workspace hover shelf. Settings tab selection remains editing-only and must not activate
  a live workspace. The menu-bar instance keeps the existing click semantics: background activation
  switches to the workspace, while an item switches to that workspace and focuses its exact
  managed window when still valid, with a same-app fallback if that window vanished.
- **Display geometry refinement:** Following installed-build feedback, each preview canvas uses the
  workspace's resolved home-display bounds rather than the union of all connected displays. The
  preview therefore has the same aspect ratio as that screen and preserves each window's relative
  position on it; windows wholly on another screen are not captured into that screen's preview.
  A second installed-build report showed empty side bars inside captured windows on an ultrawide
  display. Each one-shot capture now uses an aspect-correct size bounded by the shared thumbnail
  maximum instead of forcing every window into a 320-by-200 pixel buffer; this removes
  ScreenCaptureKit letterboxing without stretching content and reduces retained pixels where the
  window is not 16:10.
- **Privacy and safety boundary:** Captured pixels are never persisted, synced, exported, logged, or
  included in diagnostics. Preview construction never unparks, moves, resizes, raises, unhides, or
  focuses a window. Denial, revocation, capture failure, protected content, parked-window capture
  limitations, and a disabled setting all fall back to app icons and privacy-safe placeholders.
  Cache entries are discarded on semantic window-identity/geometry invalidation and app lifecycle
  teardown. Authorization is rechecked on app activation, menu presentation, and after capture.
- **Performance boundary:** Capture only final thumbnail-sized one-shot images, coalesce stale
  requests, serialize capture batches globally, cap each workspace at 32 captured items, and
  enforce hard cache count and approximate-byte ceilings before and during capture. Do
  not create an `SCStream`, background refresh timer, or full-resolution per-workspace bitmap cache.
- **Settings initial-fill refinement:** Installed-build testing showed that tabs initially displayed
  metadata icons until each workspace was selected. Settings now requests pixel enrichment for all
  active-profile workspace tabs on appearance, with the selected tab requested first. Those batches
  remain globally serialized and subject to the existing item, entry, and 24 MB cache ceilings.
- **Wallpaper refinement:** When pixel previews are enabled and Screen Recording is authorized, the
  reusable preview also resolves the current wallpaper for the workspace's home display through
  AppKit, decodes it directly to the final preview size, and lays managed windows over it. Wallpaper
  pixels share the existing 24 MB repository budget and lifecycle purge rules; the provider's small
  per-display decode cache is explicitly cleared on disable, revocation, and repository teardown.
  Dynamic, protected, or unavailable wallpaper keeps the neutral fallback rather than triggering
  any additional capture or permission request.
- **Acceptance:** Pure model tests cover geometry normalization and the three interaction modes;
  injected permission/capture tests cover no-prompt metadata fallback, grant/deny/revoke, stale
  result rejection, and cache bounds; Settings persistence proves the opt-in remains local and
  absent from profile/iCloud data. Focused menu-bar and Settings tests, complete non-hosted
  verification, an unsigned universal build, skeptical review, and a separately approved signed
  install are required. Live validation must exercise permission grant/revoke, protected or blank
  content, inactive parked workspaces, multiple windows from one app, multiple displays, hover
  dismissal, whole-workspace clicks, item clicks, and Settings tab rendering.
- **Automated evidence:** `WorkspacePreviewTests` has 20 focused tests for three-mode interaction,
  clicked-window priority with same-app fallback, geometry, explicit permission request and
  revocation, no-prompt fallback, empty-workspace suppression, hard entry/byte/item budgets,
  semantic invalidation, stale-result rejection, globally serialized byte-budget reservation, and
  non-blocking purge plus automatic deferred retry around a non-cooperative capture, home-display
  canvas selection, negative-coordinate per-screen geometry, aspect-correct bounded capture sizing
  for ultrawide half-screen windows, final-size wallpaper decoding, empty-workspace wallpaper loading
  without ScreenCaptureKit enumeration, and complete wallpaper-pixel purge on permission revocation.
  The reusable fallback also has an offscreen Retina fixture.
  Landscape and portrait Retina fixtures were rendered and inspected. The local quick verification
  script passed all 806 tests; Debug static analysis
  and an unsigned `arm64` + `x86_64` app build also passed. The Apple Development-signed universal
  daily build from `539e0bf945e9-dirty` was installed at `/Applications/WindowRanger.app`, launched
  successfully, and retained the prior daily bundle at `/Applications/.WindowRanger.previous`.
  The home-display aspect-ratio refinement was subsequently installed on 29 August 2026 from the
  same dirty source marker and relaunched as process `89169`. The installed executable, Debug dylib,
  and preview dylib match the just-built signed candidate byte for byte; the previous daily bundle
  remains recoverable at `/Applications/.WindowRanger.previous`. The per-window capture-aspect fix
  passed the 17 focused tests and the complete 802-test non-hosted suite, then was installed on
  29 August 2026 as an Apple Development-signed universal Debug build from dirty source marker
  `539e0bf945e9-dirty`. The installed executable and Debug dylib match the signed build products byte
  for byte. Fresh diagnostics session `199E96F3-BB3F-4859-B3AC-F4A8D6C55DAC` reached
  `startup-state-ready` without a new error, fault, timeout, or failed event. The previous daily
  bundle remains recoverable at `/Applications/.WindowRanger.previous`; visual validation of the
  ultrawide capture remains with the maintainer. The later Settings initial-fill policy is covered
  by a focused ordering test and the complete 803-test non-hosted suite. It was then installed on
  29 August 2026 in an Apple Development-signed universal Debug candidate from dirty source marker
  `539e0bf945e9-dirty`. The installed executable and Debug dylib match that build byte for byte;
  fresh diagnostics session `43D8C424-03A7-42CA-ADB5-CEBDEDB0EEC7` reached
  `startup-state-ready` without a new error, fault, timeout, or failed event. Live initial-fill
  validation remains with the maintainer. The wallpaper refinement subsequently passed all 20
  focused preview tests, the complete 806-test non-hosted suite, and Debug static analysis. It was
  installed on 29 August 2026 as an Apple Development-signed universal Debug daily build from dirty
  source marker `539e0bf945e9-dirty`; the installed executable, Debug dylib, and preview dylib match
  the signed build products byte for byte. Fresh diagnostics session
  `C1A6558D-F155-4441-8C6D-9FF5F3DBA4B9` reached `startup-state-ready` without a new error, fault,
  timeout, or failed event. Live wallpaper composition remains with the maintainer.

### WR-096 — Suppress unchanged periodic engine-state callbacks

- **Type:** Runtime CPU and main-thread invalidation optimisation
- **Priority:** P1
- **Status:** Done — implemented, reviewed, automated-test verified, signed daily build installed,
  runtime-sampled, and maintainer live acceptance recorded on 28 August 2026.
- **Requested:** 28 August 2026 as the second remaining optimisation after WR-095.
- **Smallest useful outcome:** Continue constructing the compact public engine state on every broad
  refresh so Accessibility trust and externally caused changes are detected, but do not enqueue its
  main-thread observer when it is semantically equal to the last scheduled state.
  Preserve every explicit engine mutation as a forced broad invalidation.
- **Functionality boundary:** Do not change refresh cadence, Accessibility discovery, layout,
  persistence, state contents, command validation, menu presentation, Settings workspace utility
  visibility, active-profile recording, focus-highlight contexts, or Shelf guide behavior. Only the
  periodic timer may suppress an identical state; startup and all command, configuration,
  lifecycle, wake, display, focus, Quick App, and recovery call sites retain their existing forced
  callback.
- **Risk:** Medium. The callback fans out to menu-bar rebuild, Settings visibility, Command Palette
  revalidation, local active-workspace recording, focus-highlight contexts, and Shelf-guide refresh.
  Comparing only `WorkspaceEngineState` at every call would be unsafe because it omits some derived
  command/UI context. Confining equality suppression to the timer preserves those broader explicit
  invalidations and narrows the remaining risk to an externally caused state change missing from
  the state model. The timer therefore retains forced callbacks while Command Palette is presented,
  preserving its periodic stale-context safety net for external focus and frame changes that are
  intentionally absent from the compact state.
- **Acceptance:** Pure policy coverage proves first/changed periodic states schedule, an identical
  periodic state skips, and an explicit identical state remains forced. Audit every observer and
  emission call site, run the focused and complete non-hosted suites, unsigned universal build,
  skeptical review, and separately approved signed daily install. Live-check workspace membership,
  Accessibility status, menu labels, Settings visibility, Command Palette context, focus highlight,
  Quick App Shelf/guide, layouts, fullscreen return, wake, and display changes. Confirm a settled
  sample no longer shows timer-driven identical observer work before comparing whole-process CPU.
- **Implemented:** The engine remembers the last state scheduled to the main queue. Its 0.75-second
  timer requests equality-aware emission; the first or changed state still schedules normally, while
  an identical state stops before dispatch when Command Palette is closed. While the palette is
  presented, the timer retains its previous forced callback so same-workspace external focus/frame
  changes continue to revalidate its richer command token. Every other existing `emitState()` call
  keeps forced semantics by default, preserving broad derived-context invalidation for explicit
  work.
- **Automated evidence:** The state-emission gate has direct coverage for its first, identical,
  changed, returned, and forced-state transitions, including each public state field independently;
  focused `WorkspaceDefinitionTests` pass 129/129. The complete quick suite passes 765/765 and the
  unsigned Debug app builds for both `arm64` and `x86_64`.
- **Review evidence:** The callback consumer and emission-call-site audit confirmed that only the
  timer opts into equality suppression. Skeptical review initially found that unconditional timer
  suppression could stale Command Palette's richer external-focus/frame context; the palette-open
  forced-emission exception corrected that blocker, and re-review found no remaining blocker.
- **Install evidence:** Signed Debug daily build `191b010f31b4-dirty` installed and relaunched from
  `/Applications/WindowRanger.app` on 28 August 2026. The installed executable is universal
  `arm64`/`x86_64`, signed by Team `44NAD22AK6` with CDHash
  `963be4627461ea84f5d9dcdf62a824d22add81ca`, and began diagnostics session
  `3879290D-9D65-4AD8-8510-FCBECC8597C1` without an observed startup failure. After the accepted
  change was committed, clean checkpoint `a249b813213a` was rebuilt, installed, and relaunched as
  PID `57120`; its universal signature verifies under Team `44NAD22AK6`, its CDHash is
  `2159ae80e6a20bb3c09fbb4cd8e6bc03d9f69feb`, and its embedded source marker has no dirty suffix.
- **Live evidence:** The maintainer exercised the installed candidate and reported no issue. A
  subsequent five-second runtime sample observed periodic `emitState(force:)` construction once but
  none of its main-thread callback consumers, consistent with identical settled state stopping at
  the gate. A separate ten-sample operational reading averaged 5.55% CPU and ranged from roughly
  155-177 MB resident memory while the session contained active workspace interactions; this is a
  checkpoint only, not evidence that WR-096 changed whole-process CPU or memory by that amount.

### WR-095 — Reuse refresh frame observations in background layout signatures

- **Type:** Runtime CPU and Accessibility-read optimisation
- **Priority:** P1
- **Status:** Done — implemented, reviewed, automated-test verified, installed, source-level
  performance verified, and maintainer live acceptance recorded on 28 August 2026.
- **Requested:** 28 August 2026 as the first remaining item after the accepted optimisation
  checkpoint and fresh installed-build baseline.
- **Baseline:** The signed installed `a3de0b817f7f-dirty` candidate, running for about 46 minutes,
  averaged 3.45% CPU across 19 settled one-second samples (0.3–6.1%). Sampler-reported process
  memory settled around 61–62 MB after macOS reclaimed pages during the run. The Mac's overall load
  was elevated, so this is an operational comparison point rather than a controlled laboratory
  benchmark.
- **Smallest useful outcome:** Build the pre-layout signature from the frames already read during
  the same broad refresh. If an enumerated window had no readable frame, retain the existing fresh
  fallback read. When WindowRanger applies visibility or geometry, perform one fresh post-write
  signature read; when it performs no write, retain the already-built signature without rereading
  every visible managed window.
- **Functionality boundary:** Preserve the 0.75-second refresh cadence, enumeration, admission,
  external-drag reconciliation, visibility/layout decisions, write ordering, post-write baseline,
  failed-frame retry, persistence, state emission, and diagnostics. A window moved externally after
  its enumeration frame was captured may be recognized on the following refresh rather than by a
  second read later in the same refresh.
- **Acceptance:** Pure tests prove a captured frame bypasses the fallback read, a missing frame still
  retries, a no-write refresh reuses its signature, and a geometry-writing refresh obtains a fresh
  post-write signature. Run the focused tests, complete non-hosted suite, unsigned universal build,
  skeptical review, and separately approved signed install. Compare a settled like-for-like sample
  against the 3.45% operational baseline and exercise external window movement plus Tiled,
  Accordion, Freeform, workspace switching, native fullscreen return, and display changes.
- **Implemented:** The broad refresh passes its captured frame map into background-signature
  construction. Signature resolution uses an observed frame when present and preserves a direct AX
  fallback for failed or unavailable enumeration frames. The refresh records whether any visibility
  or recovery layout application was attempted: ordinary no-application refreshes keep the observed
  signature, while an attempted application obtains the same fresh post-write signature used
  previously even when it ultimately has no eligible or changed targets. Explicit command and
  lifecycle paths outside the broad refresh retain their existing fresh frame reads.
- **Automated evidence:** All 24 focused Move Window/Focus tests and the complete 763-test
  non-hosted suite pass, as do test isolation, project regeneration, shell checks, diff checks, and
  an unsigned universal Debug app build containing `x86_64 arm64`. Pure coverage proves observed
  frame reuse, missing-frame retry, no-application signature reuse, and post-application rereading.
  Independent read-only trace and skeptical review found no correctness blocker across startup,
  wake, topology, manual Tiled drag, hidden/deferred windows, rejected writes, or explicit command
  paths. Integration of the helpers inside the private broad-refresh path is verified by inspection
  rather than a hosted engine test; the existing non-hosted boundary intentionally cannot enumerate
  or move live windows.
- **Installed evidence:** With explicit maintainer approval, Apple Development-signed universal
  Debug daily candidate `2c2932e1c11f-dirty` was installed at
  `/Applications/WindowRanger.app` and relaunched as PID `99804`. The installed executable exactly
  matches the built candidate; strict deep signature validation, bundle identity
  `dev.appranger.WindowRanger`, Team ID `44NAD22AK6`, `x86_64 arm64` architectures, running path,
  embedded source marker, and CDHash `1af56b2f6424d25729f731d36c3d4f6eb5835e49` were verified.
  Diagnostic session `82F35F52-2F57-4962-B3A5-7F43166B4814` reached `session/started` with the
  expected Debug build and two-display Independent mode. The previous daily candidate remains
  available at `/Applications/.WindowRanger.previous`.
- **Live and performance result:** The maintainer reported that the installed candidate appeared to
  work normally. Its current diagnostic session contains no failure, rejection, or timeout record.
  A five-second process sample confirms background-signature construction no longer contains an
  Accessibility frame-read stack; remaining frame reads belong to the single enumeration pass.
  Two settled 20-sample runs averaged 5.21% and 5.31% CPU, versus the earlier unusually low 3.45%
  operational baseline, while sampler memory moved from 102 MB to 66 MB as macOS reclaimed pages.
  System load remained high. Therefore the removed synchronous AX work is directly verified, but no
  whole-process CPU or memory reduction is attributed to WR-095 from these noisy runs.

### WR-094 — Preserve tiled order across native fullscreen Space transitions

- **Type:** Fullscreen window-lifecycle and layout-stability bug
- **Priority:** P1
- **Status:** Done — implemented, automated-test verified, installed, and maintainer live validation
  accepted on 28 August 2026.
- **Reported:** 28 August 2026 while testing the installed optimisation candidate.
- **User-observed:** With a full-screen app active, quitting it and returning to workspace 1
  reordered the workspace's tiled windows.
- **Diagnostic evidence:** Session `3F32D218-0E53-4E14-82DA-6BDBC3143794` recorded native
  fullscreen entry at `09:47:58.972Z`, then a coordinated Accessibility enumeration collapse for
  8 of 11 tracked processes. The existing 500-millisecond grace initially retained the layout
  slots, but nine still-running windows were evicted at `09:48:00.044–09:48:00.048Z` while the
  fullscreen session remained active. Chrome was rediscovered before Claude on return, rebuilding
  workspace 1 as Chrome-left/Claude-right. The maintainer's subsequent left reorder is recorded as
  changing that exact tree back to Claude-left/Chrome-right.
- **Expected:** A native fullscreen Space may suppress ordinary apps' Accessibility window lists,
  but it must not erase their workspace membership, tiled tree, ratios, or ordering. Management on
  another display must remain available, and genuine isolated window closure must remain
  authoritative.
- **Implemented:** Only the coordinated multi-application collapse policy now treats a native
  fullscreen window present in the current snapshot as a protection boundary. The affected empty
  process cohort retains its windows and layout slots throughout fullscreen, and the first
  still-collapsed snapshot after exit receives the existing bounded grace. A latched but currently
  absent fullscreen session cannot create unbounded protection. This does not turn fullscreen into
  global layout suspension. Accessibility enumeration is authoritative per application rather than
  per display, so the successfully empty cohort is protected across the Mac while currently
  enumerated windows on another display remain fully manageable. Single-application absence, a
  missing individual window from a non-empty application snapshot,
  and process termination retain their existing authority.
- **Acceptance:** Pure coverage proves protection survives longer than the ordinary grace, exit
  receives a fresh bounded grace, and isolated closure remains immediate. The complete non-hosted
  suite and unsigned universal build must pass. In a signed daily app, enter native fullscreen on
  the workspace display, remain there beyond 500 milliseconds, quit or exit fullscreen, and confirm
  exact tree order and split ratios return; repeat while using the other display and after genuinely
  closing one ordinary window.
- **Automated evidence:** All 51 focused wake/fullscreen lifecycle tests and the complete 760-test
  non-hosted suite pass with zero failures. The repository quick-verification gate and unsigned
  universal Debug app build also pass, and the built executable contains both `arm64` and `x86_64`.
- **Installed evidence:** With maintainer approval, the Apple Development-signed universal Debug
  daily candidate `a3de0b817f7f-dirty` is installed and running from
  `/Applications/WindowRanger.app` as PID `9273`. Strict deep signature validation, bundle identity
  `dev.appranger.WindowRanger`, Team ID `44NAD22AK6`, both architectures, running path, embedded
  source marker, and CDHash `baa3b8484fe18740c89f97e7ddbafc3ab0dffa31` were verified. Fresh
  diagnostic session `C8465481-04C9-401E-A746-801EF0CC8659` reached `session/started` with the
  expected Debug build and two-display Independent mode. The previous daily copy remains available
  at `/Applications/.WindowRanger.previous`.
- **Live result:** After testing the installed candidate, the maintainer reported no further issue
  and accepted the fullscreen-return behaviour on 28 August 2026. No new tiled reorder was reported.

### WR-093 — Release stale diagnostic focus after authoritative window removal

- **Type:** Runtime memory and focus-lifecycle correction
- **Priority:** P2
- **Status:** Done — implemented, reviewed, automated-test verified, installed, and live-validated
  on 28 August 2026.
- **Requested:** 28 August 2026 as the next low-risk result from the CPU and memory audit.
- **Smallest useful outcome:** When a successful application-window enumeration confirms that a
  tracked window disappeared, release its retained diagnostic `AXUIElement` and do not immediately
  cache the same stale key again if macOS still reports it as focused during that refresh.
- **Functionality boundary:** Preserve a previous still-valid external diagnostic anchor, accept a
  fresh surviving external focus, ignore WindowRanger-owned focus, and make no changes to window
  admission, focus following, command targeting, geometry writes, persistence, or refresh cadence.
- **Acceptance:** Focused policy coverage, the complete non-hosted suite, an unsigned app build,
  skeptical review, and a signed daily install checked by closing an externally focused window and
  continuing normal workspace and command interaction.
- **Implemented:** Authoritative enumeration removal now feeds one pure diagnostic-focus retention
  policy. It discards a removed previous anchor, refuses a same-refresh observation of that removed
  key, preserves a previous surviving external anchor, accepts a fresh surviving external focus,
  and ignores WindowRanger-owned focus. Failed/incomplete enumeration supplies no removed key and
  therefore cannot trigger the cleanup.
- **Automated evidence:** The focused 127-test workspace suite and complete 756-test non-hosted
  suite pass, as does the unsigned Debug app build and repository quick-verification gate. Coverage
  includes authoritative removal, a same-refresh stale observation, valid replacement and previous
  anchors, owned focus, failed enumeration, and skipped focus observation. Skeptical read-only
  review found no blocking correctness or behavior issue across lifecycle deferral, ignored-window
  eviction, WindowServer reset, unmanaged focus, or downstream command/focus behavior.
- **Installed evidence:** The Apple Development-signed universal Debug daily build for
  `a3de0b817f7f-dirty` was installed at `/Applications/WindowRanger.app`, signature-verified, and
  relaunched as PID 51498. Its embedded revision, Team ID, bundle identity, architectures, and
  running executable path were verified.
- **Live result:** In diagnostic session `91D24CE3-F196-43E1-8FDB-034D56884EEF`, successful
  enumeration evicted both closed TextEdit windows at `09:00:24.729Z`; the next focus observation
  contained no previous, current, or expected window, and neither removed key appeared again.
  Workspace switches continued to choose and verify surviving Claude and Codex windows. Command
  Palette opened on a surviving managed window, proving WR-093 did not retain or reuse the vanished
  target. Its ordinary command selection exposed the separate pre-existing WR-065 dismissal-order
  race recorded below; that did not weaken WR-093's stated cleanup boundary.

### WR-092 — Remove redundant workspace and rule work from engine refreshes

- **Type:** Runtime CPU and allocation optimisation
- **Priority:** P1
- **Status:** Done — implemented, reviewed, automated-test verified, installed, diagnostics and
  performance checked, and maintainer live validation accepted on 28 August 2026.
- **Requested:** 28 August 2026, after accepting WR-091 as the performance baseline.
- **Smallest useful outcome:** Eliminate repeated construction of valid-workspace sets, linear
  workspace layout/configuration searches, repeated active app-rule resolution, the duplicate
  window sort in the background-layout signature, and duplicate visible/hidden classification in
  one visibility pass.
- **Functionality boundary:** Preserve the 0.75-second refresh cadence, every Accessibility and
  WindowServer observation, destination-before-source visibility ordering, signature content and
  ordering, app-rule normalization, profile/workspace invalidation, persistence, state emission,
  diagnostics, and all window-management behavior.
- **Acceptance:** Focused cache-invalidation and semantic-equivalence tests, the complete non-hosted
  suite, an unsigned app build, skeptical review, and a separately approved signed daily install.
  Compare idle CPU, physical footprint, and sampled refresh stacks against the installed WR-091
  baseline without attributing unrelated Tiled or diagnostics changes to this item.
- **Implemented:** The engine now rebuilds one immutable derived index whenever its active
  workspace definitions or app-rule map changes. The index preserves first-matching duplicate
  workspace behavior, lowercased bundle matching, and valid-workspace filtering while supplying
  constant-time workspace layout/configuration and active resolved-rule lookups. Background layout
  signatures sort tracked windows once, and visibility application classifies eligible non-Quick
  App windows once before restoring the visible group and then parking the hidden group.
- **Automated evidence:** The focused 126-test workspace suite and complete 755-test non-hosted
  suite pass, as does the unsigned Debug app build and repository quick-verification gate. New
  coverage verifies duplicate-ID precedence, case-insensitive rule lookup, and rule revalidation
  after a workspace disappears. A skeptical read-only review found no functional regression; it
  confirmed all mutation sites rebuild the index, including Swift array-element writeback, and
  confirmed signature and visibility ordering remain equivalent. Engine-level observer execution
  is verified by inspection rather than a dedicated asynchronous integration test.
- **Installed evidence:** The Apple Development-signed universal Debug daily build for
  `a3de0b817f7f-dirty` was installed at `/Applications/WindowRanger.app`, signature-verified, and
  relaunched as PID 36580. A five-second process sample found no sampled active-rule resolution
  frame and only one cached workspace lookup frame; the former per-call rule resolution and
  workspace-set construction path was absent. A settled 20-sample run averaged 3.2% CPU versus the
  5.7% WR-091 baseline, while physical footprint was 72.0 MB versus about 79.1 MB and launch peak
  was 348.0 MB versus about 364 MB. That interval included one genuine workspace switch, and two
  earlier runs were interaction/settling contaminated at 6.8–8.3%, so the source-level work is
  confirmed removed but the apparent CPU and memory reduction is not yet a clean attributable
  benchmark. The switch itself completed with successful frame/position writes and exact focus
  verification in diagnostics.
- **Live result:** The maintainer exercised the installed build across the requested workspace,
  layout/configuration, app-rule, profile, persistence, and Quick App areas without finding an
  issue and accepted the result as sufficient. A future deliberately quiescent measurement may
  refine the exact performance delta, but is not required for this functionality-preserving item.

### WR-091 — Remove the macOS 27 status-item redraw loop

- **Type:** Diagnostic-backed performance bug
- **Priority:** P0
- **Status:** Done — the static-rendering correction is implemented, reviewed, automated-test
  verified, installed, performance-verified, and maintainer interaction accepted on 28 August 2026.
- **Reported:** 28 August 2026 during the deep CPU and memory optimisation audit.
- **Observed:** The installed signed Debug daily copy sustained about 46% of one CPU core while
  otherwise idle. A three-second process sample attributed 561 of 1,231 sampled main-thread stacks
  to AppKit status-item replicant updates and snapshot rendering of WindowRanger's retained custom
  display-group views. This is diagnostic-backed, not inferred from source alone.
- **Expected:** An unchanged menu-bar presentation should be effectively idle. Compact, Medium, and
  Full must retain the existing per-display ordering, widths, labels, hover feedback, workspace hit
  regions, primary/right/control click routing, menu behavior, accessibility, and appearance.
- **Implemented:** On macOS 27 and later, each standard `NSStatusBarButton` now owns only a cached 2x
  bitmap and immutable workspace geometry. The existing hierarchy is constructed offscreen solely
  when presentation or system colours change, then discarded. Normal and workspace-hover images
  are pre-rendered so pointer movement only swaps an image; no custom view remains attached beneath
  AppKit's live status button. The pre-macOS-27 composition path is unchanged.
- **Automated evidence:** The focused 46-test menu-bar suite, unsigned Debug app build, test-isolation
  gate, and complete 754-test non-hosted suite pass. New coverage checks exact rendered size, 2x
  pixel dimensions, normal/hover image availability, preserved hit targets, parent-button centring,
  informational modes, and the absence of a live custom subview. A skeptical read-only review found
  no material blockers and independently matched the geometry to AppKit's image rect.
- **Installed evidence:** The Apple Development-signed universal Debug daily build for
  `0561951a20e5-dirty` was installed at `/Applications/WindowRanger.app`, signature-verified, and
  relaunched as PID 97265. A 20-sample idle run averaged 5.7% CPU versus about 46% before the change,
  an approximately 88% reduction. The follow-up five-second sample found only single-digit AppKit
  replicant updates during genuine status rebuilds rather than the former continuous 561-of-1,231
  main-thread sample path. After two minutes, physical footprint settled to 76.5 MB versus 79.5 MB
  before the change, with a 364 MB launch peak versus 380 MB before it. The process RSS snapshot was
  about 96 MB versus 53 MB before it, so memory has no demonstrated regression in physical footprint
  but still needs a longer, like-for-like baseline before drawing an RSS conclusion.
- **Live result:** The maintainer completed the menu-bar validation and reported that all tested
  behavior worked correctly. The optimisation chain was subsequently reinstalled from clean
  checkpoint `a249b813213a`, preserving the accepted static-rendering implementation with a clean
  embedded source marker.

### WR-089 — Preview manual Tiled resize and move with intuitive BSP landing targets

- **Type:** Tiled layout interaction refinement
- **Priority:** P2
- **Status:** Done — transparent resize and the redesigned title-bar move interaction are
  implemented, reviewed, automated-test verified, installed, and maintainer accepted as of
  1 September 2026.
- **Requested:** 25 August 2026.
- **Smallest useful outcome:** When the user begins resizing a managed window in a Tiled workspace,
  visually replace every participating tile with a click-through glass placeholder that follows the
  proposed split geometry. Temporarily park only the participating real windows, commit their new
  frames once on mouse release, then remove the preview. Apply the same transaction to a genuine
  title-bar move: keep the real windows visible, retain the dragged window under the pointer, and
  show one accent-glass landing region. The centre of a target window proposes the familiar leaf
  swap; its left, right, top, and bottom regions propose inserting the dragged leaf beside that
  target while remaining inside the existing BSP model.
- **Safety boundary:** Do not hide an application, minimise a window, activate WindowRanger, or
  disturb unrelated windows. Capture exact original frames before parking participants, and restore
  them on every cancellation path. The overlay must never intercept the resize gesture. Cancel and
  remove it on a workspace, profile, participant set, display topology, lifecycle, Pause,
  full-screen, Shelf, or termination boundary; an abandoned preview must retain the last committed
  Tiled tree.
- **Acceptance:** A genuine edge or corner size change with more than one eligible Tiled participant
  starts the preview promptly; title-bar moves and WindowRanger resize commands do not. Placeholders
  use the exact proposed final frames and native glass on macOS 26 or later, with the existing HUD
  material fallback on older supported macOS versions. Once the preview begins, only bounded
  concealment writes keep the participating windows parked while pointer movement drives the hints.
  For a title-bar move, stationary real windows remain visible and only the dragged window's exact
  proposed landing frame appears as an accent-glass hint. Moving between a target's centre and four
  edges updates that hint without restructuring the committed tree; moving over the source or a gap
  removes it. Release validates and commits the latest tree once, while cancellation restores the
  dragged window to its committed frame. Focused
  deterministic tests, the complete non-hosted suite, an unsigned app build, visual inspection, and
  separately approved installed-app interaction validation are required.
- **Implemented:** A passive global pointer monitor samples drag updates at a bounded 30 Hz without
  broad window enumeration. The engine retains the committed BSP tree as an immutable session
  baseline, captures exact participant frames and the dragged edge/pointer anchor, emits proposed
  frames to one tokened nonactivating overlay, parks only the participating windows, and projects
  subsequent geometry directly from the pointer. It applies the final participant frames once on a
  fully revalidated release or restores the captured originals on cancellation. On macOS 26 and
  later, untinted clear Liquid Glass tiles sit in one system glass container over the visible
  desktop; a fine border in the glass-owned content view preserves the lightweight landing hint.
  macOS 14–25 use the HUD-material fallback on the same transparent panel. The focused-window border
  is suppressed for the transaction. Workspace/layout commands, Quick App Shelf commands, Pause,
  profile changes, display/session lifecycle changes, WindowServer replacement, and quit explicitly
  cancel the preview. A position-only title-bar move now starts the same tokened overlay from the
  committed frames, resolves subsequent targets without consulting the parked AX windows, and
  originally animated changed tile frames over 160 ms and committed a proposed leaf swap. The
  1 September redesign replaces that move-only presentation: participants are no longer parked,
  the real layout remains recognisable, and a single accent landing tile follows the pointer. A
  centre target still swaps leaves; an edge target removes and collapses the source branch, then
  inserts the source beside any hovered leaf with a new equal horizontal or vertical split. Release
  commits that exact proposed tree; release over the source or a gap and every cancellation boundary
  restore the captured frames. The accepted resize transaction is unchanged.
- **Review correction:** A display-configuration change now reports whether it directly dismissed an
  active preview and immediately restores the focused-window border before the engine completes its
  tokened cancellation. This prevents the border remaining suppressed after the presenter has
  already cleared its token; a focused regression test covers both active and already-empty paths.
- **Automated evidence:** Twelve focused preview-policy, transition, coordinate-conversion,
  dragged-edge projection, transparent glass-container, clear-glass hint/border,
  native/fallback-surface, stale-token, and opt-in render tests pass. All 37 Tiled tree tests pass,
  including concealed move target resolution from immutable committed frames. The complete
  non-hosted suite passes all 754 tests, and the unsigned universal Debug app build succeeds for
  both `arm64` and `x86_64`.
- **1 September redesign evidence:** All 56 focused Tiled tree and preview tests pass, covering
  centre swapping, four-direction insertion, nested source collapse and target splitting, invalid
  targets, centre/edge hysteresis in both live-preview and fallback reconciliation, the 120-point
  minimum-frame preflight, and the accent landing surface. The complete non-hosted quick checkpoint
  passes all 870 tests, including project generation, test isolation, release-ledger, Sparkle-feed,
  and Stable Homebrew workflow checks. A skeptical read-only review found no remaining material
  issue after its jitter and minimum-frame findings were corrected.
- **Installed follow-up:** The maintainer found that some attempted title-bar moves still entered
  the resize presentation. Diagnostics confirmed correlation `manual-resize-95D95A89` concealed
  three participants and committed changed horizontal split ratios, so this was a real gesture
  classification fault rather than visual uncertainty. Resize had first refusal and treated any AX
  size delta over two points as sufficient evidence. Gesture start now prefers an edge-aware move
  classification: a resize is accepted only while the pointer is on every inferred changing edge;
  otherwise meaningful position displacement begins a move even when AX reports transient size
  noise. Once either tokened session begins, its intent remains locked through release. Review also
  tightened edge matching to the real perpendicular edge span, preventing a distant pointer that
  merely shares one coordinate from claiming a resize. The updated 61-test Tiled tree and preview
  domain passes, including noisy title-bar movement, leading and trailing edge resizes, corner-edge
  agreement, and out-of-span rejection. A replacement installed interaction check is still
  required.
- **Visual evidence:** The first installed candidate proved the exact 1+2 split and interaction but
  its nearly opaque backing, tint, wash, mask, and outline visually flattened the native material.
  Those custom layers are removed in the refined candidate; AppKit's live refraction over real
  window content was accepted as a better direction. The concealed-content candidate then proved
  too opaque for a transient landing hint. The lighter clear-glass candidate then made app content
  visible beneath the tiles, and the clean-stage candidate again lost transparency. The revised
  transaction instead removes only participating windows from view and leaves the transparent glass
  over the desktop; the maintainer accepted that resize interaction. Animated move behavior requires
  its own installed interaction check.
- **Installed evidence:** The signed universal daily build for `0561951a20e5-dirty` is running from
  `/Applications/WindowRanger.app` as PID 624 (CDHash
  `fc590a046f823ae65c1de134d8c6e0d62cd861be`). Its Apple Development signature, Team ID
  `44NAD22AK6`, bundle identity, `x86_64` and `arm64` architectures, embedded revision, and running
  path were verified. Fresh diagnostics session `AC7F3B64-126F-43C9-A3C9-C4BF5EEF77AB` reached
  `startup-state-ready` without a diagnostic error or fault. This installed build contains the
  accepted resize transaction and the new animated move extension; move interaction remains
  unaccepted.
- **1 September installed candidate:** The signed universal Debug daily for
  `9f4e673a1fd7-dirty` is running from `/Applications/WindowRanger.app` as PID 46143. Its
  `dev.appranger.WindowRanger` bundle identity, Team ID `44NAD22AK6`, `x86_64` and `arm64`
  architectures, embedded revision, running path, and strict deep signature were verified. Fresh
  diagnostics session `2B1A5BEF-7080-4431-8810-5B10EDD1DFDD` reached `startup-state-ready` without
  an error or fault in the inspected startup tail. The previous accepted daily remains recoverable
  at `/Applications/.WindowRanger.previous`; directional move interaction is awaiting maintainer
  acceptance.
- **Gesture-classifier replacement candidate:** The edge-aware follow-up was installed as a new
  Apple Development-signed universal Debug daily at `/Applications/WindowRanger.app`, retaining the
  preceding candidate at `/Applications/.WindowRanger.previous`. The running process is PID 49730;
  bundle identity `dev.appranger.WindowRanger`, Team ID `44NAD22AK6`, embedded revision
  `9f4e673a1fd7-dirty`, `x86_64` and `arm64` architectures, running path, and strict deep signature
  were verified. Fresh diagnostics session `245C9D7B-DBCB-4613-9432-F7C775807155` reached
  `startup-state-ready` without an error or fault in the inspected session. The maintainer then
  exercised the installed interaction and confirmed that the move-versus-resize misclassification
  was resolved and the resulting feel was accepted.
- **Final checkpoint:** The complete quick verification passes all 875 non-hosted tests after the
  accepted classifier correction, together with the release-ledger, Sparkle-feed, Stable Homebrew,
  project-generation, and test/archive-isolation checks.

### WR-087 — Copy a workspace layout without creating a preset library

- **Type:** Workspace Settings convenience
- **Priority:** P2
- **Status:** Done — implemented, automated/visual-build verified, installed, and interaction-validated.
- **Requested:** 25 August 2026.
- **Decision:** The first named layout-preset and desk-arrangement experiment duplicated Profiles,
  Application Rules, and workspace layout settings. Remove that extra persistence/UI surface and
  retain only the useful low-level action.
- **Smallest useful outcome:** In a workspace's Layout inspector, choose another workspace in the
  edited profile and copy its Freeform, Tiled, or Accordion style plus orientation, gaps, and
  padding. Preserve destination identity, Home Display, app rules, and live window membership.
- **Acceptance:** The action is unavailable with one workspace, uses the same active/inactive
  profile editing boundary as other workspace settings, applies to the live engine when editing the
  active profile, persists normally, and participates in native Undo. It creates no named object,
  sync schema, import/export content, or second Settings destination.
- **Automated evidence:** Repository quick verification passes all 739 non-hosted tests with zero
  failures. Focused coverage proves layout style/configuration copy, preservation of destination
  identity and Home Display, native Undo, and isolation when editing an inactive profile. The
  universal unsigned Debug app builds successfully.
- **Visual evidence:** The Light and Dark production Workspace Settings renders contain the native
  **Copy Layout** menu in the existing Layout section with clear scope copy and no extra destination;
  the Light render was inspected at Retina resolution. The broader renderer was stopped after these
  required pages were written because it continued through unrelated Settings destinations.
- **Installed evidence:** With maintainer approval, signed universal Debug daily candidate
  `135628eaca62-dirty` (CDHash `1065a60f4a482b1dd6b1b435a2b02ef442e6c057`) is installed and
  running from `/Applications/WindowRanger.app` as PID `62473`. Strict signature, Apple Development
  authority, Team ID `44NAD22AK6`, bundle identity, both architectures, exact built/installed
  executable and Debug dylib hashes, and running path were verified. Startup session
  `15F94716-C2D0-415E-A49F-C855F4E276B7` reached `startup-state-ready`; Notes and both Ghostty
  windows were prepared as Shelf groups. The previous daily remains recoverable at
  `/Applications/.WindowRanger.previous`.
- **Live result:** The maintainer confirmed the installed **Copy Layout** action appears to work when
  copying between workspaces; the destination accepted the selected layout without an observed
  interaction problem. Automated coverage closes inactive-profile isolation, preservation of
  destination identity and Home Display, profile-backed persistence, and native Undo through the
  same mutation path.

### WR-088 — Optionally restore and launch configured apps when applying a profile

- **Type:** Profile activation research
- **Priority:** P2
- **Status:** Needs decision — user concept recorded for refinement, not approved for implementation.
- **Requested:** 25 August 2026.
- **Product value:** Profiles should be able to feel like complete Writing or Coding environments,
  not merely rules that wait for applications to appear. Two independent per-profile options could
  recover eligible windows from configured applications and launch configured applications that
  are not running.
- **Recommended starting boundary:** Consider only enabled Application Rules with an explicit
  workspace assignment as configured launch targets. Keep Quick Apps under Shelf control. Default
  both options off, launch only after an explicit manual **Use Profile** action, never focus or
  activate each launched app, and route delayed windows through the normal rule/admission path.
- **Decisions required:** Define “back to the screen” when a profile contains inactive workspaces;
  decide hidden versus minimized handling; decide whether automatic dock/topology/Game Mode changes
  may ever launch apps; specify launch order, failure/timeout feedback, multi-display behavior,
  duplicate instances, protected full-screen sessions, and how Undo/profile supersession cancels
  pending launches.

### WR-086 — Make Shortcut Guide contextual while Quick App Shelf is open

- **Type:** Shortcut Guide and Quick App Shelf integration
- **Priority:** P2
- **Status:** Done — implemented, automated-test verified, visually checked, installed, and
  interaction-validated with the multi-window Ghostty Shelf.
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
  `cafbe4002b09` (CDHash `4802cb0367835554f90bd4f91b7f1810c19b9e82`) is installed and
  running from `/Applications/WindowRanger.app` as PID `22617`. Its strict signature, Apple
  Development authority, Team ID `44NAD22AK6`, canonical bundle identity, embedded source marker,
  `x86_64` and `arm64` architectures, running path, and exact built/installed executable and Debug
  dylib hashes were verified. Startup session `C930CA8B-ADA7-4D6D-9A84-9B266EC91EE9` reached
  `startup-state-ready` and prepared Notes as a one-window group and Ghostty as a two-window group.
  The previous daily remains recoverable at `/Applications/.WindowRanger.previous`.
- **Live result:** The maintainer confirmed the installed guide works as expected: with the
  two-window Ghostty Shelf open it appeared opposite the top Shelf with the correct Quick App Shelf
  labels and Left/Right axis, remained click-through, dismissed on release, preserved the selected
  window's Focus Border, and showed no Arrange guide. While Navigate remained held, each Shelf
  open/close updated the guide immediately. Diagnostics corroborate the same-display context switch:
  the ordinary Navigate guide reported 11 secondary actions, each presented Shelf group reported
  two Ghostty windows and changed the guide to nine, and each hide returned it to 11 without a
  modifier release. No Arrange-family presentation was requested during the acceptance sequence.

### WR-085 — Treat each Quick App as an all-window Shelf group

- **Type:** Quick App Shelf ownership and interaction change
- **Priority:** P1
- **Status:** Done — all-window grouping, layouts, navigation, transitions, dynamic membership,
  focus-loss dismissal, lock/wake preservation, and final restoration are live-validated.
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
- **Automated evidence:** 61 focused Quick App tests pass, covering same-process grouping,
  cross-process rejection, stable cycling, exact-member removal, one-for-one native-tab handoff with
  retained group members, legacy persistence, and seven-window Carousel/Accordion geometry at all
  four edges. The live-settings propagation, visible-window stacking, post-activation restacking,
  rapid transition containment, and selection-focus handoff regression tests, plus all 32 tests in
  `QuickAppShelfTests`,
  pass. The complete
  non-hosted suite passes 732 tests with zero
  failures or skips. Test isolation, shell syntax, release-build registry, Sparkle feed workflow,
  project generation,
  Release static analysis, unsigned universal Release build, and Stable/Beta DMG build and
  verification all pass (25 August 2026).
- **Live validation remaining:** Repeat the two-window Ghostty case across direct toggle and
  restart. Then check both layouts, app-wide hide/show, Previous/Next and arrow navigation, adding
  and closing one Ghostty window while presented, lock/wake, and final restoration to the original
  workspaces and frames. Direct rapid switching across configured applications, dynamic membership,
  and focus-loss dismissal are accepted below.
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
- **Retest refinement:** Candidate `e76ac3c48cb2` worked when Ghostty was selected first, but still
  showed Notes alone when Notes was selected first. Its trace recorded all three windows being
  raised before Notes finished becoming frontmost. Unlike navigation to another Shelf app,
  activation of the already-selected app did not run a post-activation group reconciliation, so
  the final Notes activation could undo the neighbour stacking. The fix now restacks the group
  after every presented Shelf app activation; selection changes only when the activated app
  differs.
- **Rapid-cycle live defect:** The maintainer exercised settings and navigation across one- and
  two-app Carousel and Accordion configurations. Diagnostics confirmed those settings, both
  Notes-first and Ghostty-first presentation, exact-window arrow navigation, post-activation
  restacking, and contextual guide updates all worked. With one visible app, however, a rapid third
  Next Window press landed after Ghostty had hidden and before Notes finished showing. Window
  cycling only recognised a currently presented Shelf, so that press escaped into the ordinary
  workspace cycle and its activation immediately closed the incoming Notes Shelf. Window cycling
  now remains routed to the Shelf for the complete hide/show transition, matching directional
  focus; repeated presses advance from the pending app selection and cannot target workspace
  windows during the gap.
- **Selection-handoff live defect:** On candidate `44026336506e`, Next Shelf Window correctly
  changed Notes to Ghostty and laid out both Ghostty windows, but hiding Notes briefly reactivated
  the window that preceded the Shelf. The incoming show treated that expected rebound as competing
  focus, immediately hid Ghostty with `another-app-focused-during-show`, and allowed the following
  command to reach ordinary workspace cycling. A bounded selection-focus handoff now preserves
  only that exact preceding process for two seconds and clears as soon as the incoming Shelf app
  activates. Unrelated application activation and expired handoffs still dismiss the Shelf.
- **App-switch latency follow-up:** The maintainer confirmed the handoff candidate worked but felt
  very slow. Its trace measured about 35 ms for cycling between Ghostty windows, about 0.4 seconds
  to switch applications into Ghostty, and about 1.1 seconds to switch into Notes. Notes had already
  been shown and activated before a redundant post-activation full membership reconciliation added
  roughly another half-second. Activation now performs only the required frame/raise restack;
  topology and membership remain owned by the existing refresh and lifecycle paths.
- **Direct-focus follow-up:** The maintainer confirmed Notes still takes noticeably longer than
  Ghostty to become frontmost and observed the ordinary workspace app receive focus between the
  outgoing Shelf app hiding and Notes activating. Application switches now reverse that order: the
  outgoing Shelf app remains presented and frontmost while the incoming application's exact windows
  are staged and unhidden, focus transfers directly to the incoming Shelf app, and only its observed
  activation permits the outgoing app to hide. Rapid requests remain queued until that activation,
  an already-active or palette-owned presentation completes without waiting for a notification, and
  a closed incoming app launches without activation so it cannot create the same workspace-focus
  gap. Unrelated activation still abandons or dismisses the transition.
- **Direct-focus live result:** The maintainer reported the installed direct handoff worked well.
  Its diagnostic trace recorded three clean Ghostty/Notes transfers with no abandoned handoff:
  show-focus-hide completion took about 0.19 to 0.28 seconds, the incoming target activated, and the
  outgoing application then confirmed hidden. No ordinary workspace focus was observed between
  Shelf applications. This accepts the one-visible-app rapid application-switch and workspace-focus
  containment regression; Notes' own activation can still visibly trail the initial transfer.
- **Dynamic-removal live defect:** Adding a third Ghostty window while the Shelf was presented
  worked and immediately laid out all three windows. Closing it removed the exact member, but the
  two survivors kept their three-window Carousel frames until the Shelf was hidden and shown again.
  Diagnostics confirmed the authoritative enumeration path pruned the closed key from the session
  before the general group reconciler ran; the reconciler then saw an already-current two-window
  membership and omitted the required relayout. Presented membership pruning must carry its own
  changed signal into the shared group layout, while hidden-session pruning remains write-free.
  The authoritative pruning path now preserves that signal, logs the exact group count change, and
  invokes the shared layout only for a presented session. Policy regression coverage passes, as do
  all 732 non-hosted tests in quick local verification.
- **Dynamic-membership live result:** On installed candidate `f412302c01bc`, the maintainer
  confirmed that opening a third Ghostty window laid out the enlarged group correctly and closing
  it immediately resized the two survivors. This accepts the presented add/remove membership case.
- **Focus-loss live result:** The maintainer confirmed that intentionally focusing an unrelated
  application dismissed the Shelf, hid both Ghostty windows together, retained the unrelated
  application's focus without flicker, and reopened the two-window group correctly. This accepts
  focus-loss dismissal and the immediate app-wide hide/reopen path.
- **Lock/wake live defect:** The maintainer initially confirmed the windows returned on their
  correct screens after locking and unlocking, then noticed that some positions had changed.
  Diagnostics show no coordinated session-suspension signal. At `15:16:39Z`, the first global-empty
  Accessibility snapshot was deferred, but the following successful empty per-application
  snapshots evicted all 14 tracked windows, cleared the two-window Ghostty Shelf session, and
  retained Notes only because its unhide was still pending. About four seconds later, readmission
  rebuilt workspace layouts from fresh discovery: the two Accordion windows on workspace 2 swapped
  positions, as did the two Tiled windows on the secondary display. Lock must enter the existing
  suspension boundary before empty snapshots can erase exact membership and layout order. The app
  now observes macOS's distributed screen-lock and screen-unlock notifications as a paired lifecycle
  source alongside the existing system, display-sleep, and fast-user-switch signals. Lock enters the
  existing write-suppressed suspension path immediately; unlock starts the same bounded fresh-AX
  reconciliation, and any independently observed sleep/session source must still receive its own
  matching resume. The first candidate passed all 46 focused lifecycle tests, all 735 non-hosted
  tests in repository quick verification, and an unsigned universal Debug app build; its signed
  lock/unlock validation exposed the notification-order race below.
- **Lock/wake retest defect:** On installed candidate `599076fda783`, the maintainer confirmed every
  workspace window retained its correct screen and exact position after lock/unlock, accepting the
  layout-order preservation part of the fix. Ghostty remained visible after unlock until the Shelf
  shortcut was invoked twice. Diagnostics show the Shelf was presented with both Ghostty windows at
  `15:37:51Z`; a successful-empty Accessibility collapse across multiple still-running applications
  evicted both Ghostty identities and cleared its Shelf session at `15:37:59.787Z`. The distributed
  screen-lock notification arrived 157 milliseconds later. Wake therefore restored only the
  retained hidden Notes session and preserved visible Ghostty focus. The first later shortcut logged
  `shown` with zero unhide attempts because Ghostty was already visible; the second hid it normally.
- **Lock-race follow-up implemented:** A successful-empty collapse spanning at least half of
  multiple still-running tracked applications is now non-authoritative for a bounded 500-millisecond
  grace period, allowing the delayed screen-lock signal to enter the existing suspension boundary.
  The cohort can expand from a partial to a global collapse during that grace. If no lifecycle
  signal arrives, the collapse becomes authoritative after the grace; disappearance in only one
  application remains immediate. Diagnostics record the deferred process count and grace. All 49
  focused lifecycle tests and all 738 non-hosted tests in repository quick verification pass,
  including the observed partial collapse, a fully empty read 125 milliseconds later, the lock
  signal at 160 milliseconds, grace expiry, and ordinary single-application closure. Signed live
  validation is accepted below.
- **Lock-race live result:** On installed candidate `cafbe4002b09`, the maintainer reported the
  lock/unlock behavior looked good. Diagnostics show the expected staged Accessibility collapse:
  11 of 15 tracked processes were deferred first, followed 161 milliseconds later by all 15. The
  screen-lock signal then arrived 47 milliseconds later with all 18 managed windows and the Quick
  App session retained. Ghostty's lock-driven focus loss hid the two-window group before suspension;
  wake restored both Notes and Ghostty as hidden application sessions. The first post-unlock Shelf
  shortcut performed a real unhide and laid out both Ghostty windows, and the next shortcut hid the
  group normally. No managed window was evicted during the lock transition, and the maintainer
  confirmed workspace windows retained their correct screens and positions. Wake verification's
  sole degraded mismatch was a BetterDisplay window retaining its own 1,200-point width after three
  successful resize requests; it did not alter the accepted Shelf state or workspace ordering.
- **Installed evidence:** With maintainer approval, signed universal Debug daily candidate
  `cafbe4002b09` is installed and running from `/Applications/WindowRanger.app` as PID `22617`.
  The built and installed executable and Debug dylib match exactly; strict signature validation,
  canonical bundle identity, Team ID `44NAD22AK6`, both `x86_64` and `arm64` architectures, running
  path, embedded source marker, and CDHash `4802cb0367835554f90bd4f91b7f1810c19b9e82`
  were verified. Startup session `C930CA8B-ADA7-4D6D-9A84-9B266EC91EE9` prepared Notes as a
  one-window group and Ghostty as a two-window application group, then reached
  `session/startup-state-ready`. This candidate includes the direct show-focus-hide application
  handoff, dynamic window-removal relayout, live Settings propagation, WR-086's contextual Shortcut
  Guide, the WR-085 screen-lock suspension fix, and the pre-notification coordinated-collapse
  grace. Startup smoke and the lock/unlock interaction are accepted above. The previous daily copy
  remains recoverable at
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

- **Type:** Integration contract and CLI
- **Priority:** P2
- **Status:** Source implementation and signed installed validation are complete for the packaged
  WindowRanger CLI v2 peer correction. Complete PATH/UI and mutating configuration validation plus
  the separate DesktopRanger adapter remain.
- **Source:** `docs/desktop-ranger-integration.md`
- **Requested outcome:** Define a versioned, non-interactive WindowRanger command contract that gives
  first-party callers access to every stable user-facing action and persisted setting without giving
  plugins arbitrary shell access, raw Accessibility identities, preference-file access, or a second
  workspace engine.
- **Acceptance:** Choose the initial query/control allowlist, request/response/error envelopes,
  privacy grants, compatibility and migration policy, same-user authenticated IPC, designated-signing
  checks, deadlines, cancellation, idempotency, and relaunch/concurrency semantics. Converge every
  exposed UI and CLI operation on the same validation and engine path. Test missing or incompatible
  peers, malformed and oversized messages, wrong signer/path substitution, stale or duplicate
  operations, timeouts, cancellation, late replies, and owner relaunch. Keep the integration
  unavailable or simulated until signed two-app validation passes without weakening macOS protections
  or changing the Apple Dock.
- **Implemented:** The app embeds a separately signed thin client and exposes protocol v2 for status,
  capabilities, private-by-default workspace listing, the compatibility workspace/layout/Pause
  commands, discovery and invocation of every stable first-party action, and complete versioned
  configuration export, validation and optimistic whole-document replacement. Actions resolve a
  fresh app-owned context and route through the existing typed dispatcher; complete settings route
  through the canonical SettingsStore plus app-owned login-item, updater and onboarding services.
  Per-user local IPC verifies same user, exact resolved paths, Team ID and code identifiers on both
  peers. Request IDs have a bounded replay cache, unavailable apps are launched from the helper's
  enclosing bundle, expired requests are rejected before dispatch and after asynchronous context
  capture, concurrent identical retries coalesce, and code-only failures map to deterministic exit
  categories. Complete configuration decoding rejects unknown fields rather than dropping typos;
  apply requires a current revision and explicit replacement flag. Turning iCloud on and replacing
  its cloud copy are separate actions with distinct exact confirmation tokens, so pull-first sync
  cannot make an atomic apply report success for a different document.
  General Settings can conservatively add/remove `~/.local/bin/windowranger` without administrator
  access, unrelated shell-file edits, or lost startup-file metadata. `windowranger skill` prints or
  safely writes a deterministic agent skill with no runtime data.
- **Automated evidence:** All 858 non-hosted tests pass, including strict protocol/configuration
  shape checks, no-mutation invalid apply, cloud confirmation policy, async deadline/late-completion
  handling, concurrent retry coalescing, 128 KiB transport, peer rejection, safe PATH and skill
  export. Unsigned Debug app and helper builds succeed as universal arm64/x86_64 executables, and the
  generated skill passes the Codex skill validator. Prior v1 signed arm64 and universal bundles
  passed nested-signature validation. Exact v2 installed PATH/UI interaction, mutating configuration,
  and DesktopRanger two-app checks remain required.
- **User-observed signed-package failure:** During the public Homebrew 1.0.0 install test on
  30 August 2026, `windowranger version` correctly reported 1.0.0 build 12, but every IPC-backed
  command rejected the running app with `The WindowRanger command peer is not the bundled
  executable.` The same exact DMG-installed build failed before Homebrew replacement, so this is not
  a Cask fault. The app and helper have the expected Team ID, identifiers, signatures, universal
  architectures, and installed paths. Apple documents that `SecCodeCopyPath` returns the bundle
  directory for bundled code; the CLI instead compares that result with
  `Contents/MacOS/WindowRanger`. The smallest security-preserving repair is to compare the known app
  bundle root while retaining the same-user, Team ID, code-identifier, and exact helper checks. The
  1.0.1 correction does exactly that and adds a policy regression test.
- **Signed installed correction evidence:** The exact notarized 1.0.1 build 13 DMG was installed at
  `/Applications` before publication. Its embedded universal CLI completed authenticated status,
  capabilities, 37-action discovery, nine-workspace discovery, full configuration read/validation,
  and skill generation. Eight concurrent signed clients succeeded, and signed IPC recovered after a
  full app quit and relaunch. This exercises both app-to-helper and helper-to-app peer verification
  without weakening any identity check.

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
- **New-machine correction:** The wizard window is now a floating auxiliary surface that joins all
  native macOS Spaces, so exercising workspace shortcuts cannot strand it elsewhere. Its
  Accessibility step shares the bounded, prompt-free permission monitor used by Settings, refreshes
  on appearance and app activation, and continues polling while the grant is missing so an external
  System Settings change turns green without a second click. Ten focused onboarding and 24 Utility
  Settings tests pass as part of the 216-test combined verification and complete 814-test suite.
  Release static analysis and the unsigned universal Release build pass. Signed live validation remains.
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
- **Status:** Live validation — the selected Displays refinement passes the complete automated and
  design gate and is installed as a signed daily candidate; hands-on interaction remains pending.
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
- **Eighth user-observed follow-up:** Replace the Profile Library master list with top tabs showing
  a large icon and profile name, plus a trailing add-profile tab. Combine Profiles and Profile
  Switching into one destination so the selected profile can be edited and assigned to this Mac's
  Default, Game Mode, docked, undocked, and exact-display contexts in one place. Complete this
  Profiles interaction before applying any similar tab treatment to Workspaces. The maintainer
  selected visual direction 3: a restrained icon-tab strip with context badges above a compact
  identity/status inspector and wider profile-centric automatic-use editor.
- **Eighth follow-up boundary:** Preserve the reusable/synced profile library and existing Mac-local
  `LocalProfileState` schema. Tab selection, creation, and duplication change only the Settings edit
  target; **Use Profile** remains the explicit activation/manual-pin action. Automatic assignments
  remain ordered and single-owner, may re-evaluate the live profile, and must preserve the selected
  Settings tab. Default cannot be unassigned; optional Game Mode, docked, and undocked assignments
  can be assigned to or removed from the selected profile while naming any current owner. Exact
  display setups remain individually reassignable/removable, and the current topology targets the
  selected rather than implicitly active profile. Keep the sidebar editing-profile selector for
  Displays, Workspaces, Applications, and Quick App Shelf; do not redesign those pages in this pass.
- **Eighth follow-up acceptance:** Remove the standalone Profile Switching sidebar destination while
  preserving its saved-selection and search routes through Profiles. The tab strip remains usable
  with long names, many profiles, minimum Settings width, keyboard focus, and VoiceOver. Focused
  coverage proves single-owner assignment/removal, creation selection without activation,
  edit-target preservation during automatic activation, exact-topology reassignment, legacy
  routing, and merged search. Render the production screen at wide, compact, Light, Dark, inactive,
  and several-profile states; compare it with selected direction 3; then run the complete non-hosted
  gate and unsigned universal build before requesting a signed daily install.
- **Ninth user-observed follow-up:** Replace the Workspaces master-list column with a horizontal row
  of visual workspace tabs and a trailing add tab. The maintainer selected direction 2: each tab
  uses a truthful miniature of its Freeform, Tiled, or Accordion layout, with the workspace name and
  key beneath it; the selected workspace then uses a compact Details panel beside the wider Layout
  and Repair inspector.
- **Ninth follow-up boundary:** This is a presentation and interaction recomposition, not a new
  workspace model. Preserve stable UUID selection, profile-owned definitions/order, drag and
  accessible reordering, add/duplicate/delete, unique names and keys, search deep links, Home
  Display roles, derived shortcuts, layout copy/reset, legacy geometry, live repair, inactive-profile
  isolation, and the transient Tiled link state. Miniatures describe saved layout style only and do
  not represent or activate current windows. Compact Settings must retain every action without
  requiring a second master-list screen.
- **Ninth follow-up acceptance:** Wide and compact layouts keep the tab strip, truthful layout
  miniatures, selected-workspace identity, and all existing controls usable with keyboard and
  VoiceOver. Deterministic coverage proves selection reconciliation across reorder/delete/profile
  changes, search-to-tab selection, CRUD/reorder behavior, layout-preview semantics, and no live
  activation side effect. Render production Light/Dark, Freeform/Tiled/Accordion, long-name,
  many-workspace, conflict, and minimum-width states against selected direction 2; then run the
  complete non-hosted gate, static analysis, universal build, and skeptical review before requesting
  a signed daily install.
- **Tenth user-observed follow-up:** After installing the visual-tab candidate, place Duplicate and
  Delete together on one balanced row and remove the redundant visible Move Left/Right buttons.
  Drag reorder remains the primary pointer interaction; context-menu Move Left/Right and VoiceOver
  Move earlier/later remain available as non-drag alternatives.
- **Eleventh user-observed follow-up:** The two derived workspace shortcuts consumed too much space
  and their filled keycaps looked like editable shortcut recorders. Replace them with a compact
  Generated shortcuts summary using short action names and plain read-only shortcut text. State
  directly that the Workspace Key above updates both commands and global Shortcuts owns their
  modifiers.
- **Tenth/eleventh follow-up installed candidate:** With explicit maintainer approval on 28 August
  2026, the consolidated Duplicate/Delete row and compact Generated shortcuts summary were built,
  signed, installed, and relaunched as Debug daily candidate `539e0bf945e9-dirty` from
  `/Applications/WindowRanger.app` as process `9508`. Strict signature validation, Apple Development
  authority, Team ID `44NAD22AK6`, canonical bundle identifier, embedded dirty source marker,
  universal `x86_64 arm64` architectures, running executable path, and byte-for-byte equality with
  the just-built executable and Debug/preview dylibs were verified. The previous daily remains
  recoverable at `/Applications/.WindowRanger.previous`; hands-on visual and interaction validation
  remains pending.
- **Twelfth user-observed follow-up:** In Tiled geometry, Keep equal placed its checkbox after the
  label while Keep all sides equal placed it before the label, so the related controls looked
  mirrored and did not align. Use one shared label-then-checkbox row and the same wide-layout column
  for both link controls; preserve the stacked compact fallback and existing link behavior.
- **Twelfth follow-up installed candidate:** With explicit maintainer approval on 28 August 2026,
  the equality-row alignment and dedicated Tiled visual fixture were built, signed, installed, and
  relaunched as Debug daily candidate `539e0bf945e9-dirty` from
  `/Applications/WindowRanger.app` as process `14239`. Strict signature validation, Apple
  Development authority, Team ID `44NAD22AK6`, canonical bundle identifier, embedded dirty source
  marker, universal `x86_64 arm64` architecture, running executable path, and byte-for-byte equality
  with the just-built executable and Debug/preview dylibs were verified. The previous daily remains
  recoverable at `/Applications/.WindowRanger.previous`; hands-on Tiled Settings validation remains
  pending.
- **Thirteenth user-observed follow-up:** Displays is functionally correct but exposes its storage
  model as three disconnected steps: choose abstract Unified/Independent terminology, edit reusable
  role names in one list, then mentally match those names to physical monitors in another list.
  Replace the mode picker with two outcome-led visual choices: **Switch together** shows both
  displays on one workspace and retains **Unified** only as a secondary term; **Switch separately**
  shows different workspaces and retains **Independent** as a secondary term. Combine each role's
  profile-owned name and this Mac's physical-monitor picker into one mapping row, with plain
  Connected, Disconnected, Needs attention, or Not assigned status instead of fingerprint jargon.
  The selected direction uses one grouped native surface and preserves the existing Settings
  sidebar, role CRUD, menu-bar icon ownership, safe fallback, profile/iCloud boundary, and local
  `WorkspaceDisplayPin` persistence without a schema or runtime-behaviour change.
- **Thirteenth follow-up acceptance:** The visual choice diagrams, selected state, combined mapping
  rows, sync/local labels, status copy, add/delete actions, and wide/compact reflow match the approved
  mockup in Light and Dark appearance. VoiceOver exposes outcome, selection, role identity, local
  monitor, and textual status without relying on diagrams or colour. Focused Settings tests, a
  Displays-only production render, the complete non-hosted gate, and the unsigned app build pass
  before a separately approved signed daily install.
- **Thirteenth follow-up implementation and evidence:** Displays now leads with native visual
  **Switch together** and **Switch separately** choices while retaining Unified and Independent as
  secondary terms. Each display role uses one row for its profile/iCloud name, this Mac's physical
  monitor, plain textual connection status, and delete action; the existing store and persistence
  operations are unchanged. Wide Light/Dark and 760 x 560-point compact Dark production renders
  pass, with compact mode stacking the choices inside the existing scrollable Form. Full and focused
  comparisons against the selected mockup have no remaining P0-P2 mismatch. Focused Settings
  coverage passes 138 tests, the complete non-hosted suite passes 814 tests with zero failures, and
  the unsigned Debug app builds successfully as universal `x86_64 arm64`. Pointer, keyboard,
  VoiceOver, and real-monitor interaction remain signed installed-app validation.
- **Thirteenth follow-up installed candidate:** With explicit maintainer approval on 29 August
  2026, signed universal Debug daily candidate `2956284c3097-dirty` was installed and relaunched
  from `/Applications/WindowRanger.app` as process `61541`. Strict signature validation, Apple
  Development authority, Team ID `44NAD22AK6`, canonical bundle identifier, embedded dirty source
  marker, `x86_64 arm64` architectures, running executable path, and byte-for-byte equality of the
  installed executable and Debug/preview dylibs with the just-built candidate were verified. The
  previous daily remains recoverable at `/Applications/.WindowRanger.previous`; hands-on Displays
  Settings validation remains pending.
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
  live engine or selection state. Profiles now combines the reusable library, explicit activation,
  and this Mac's profile-centric automatic-use assignments; the legacy Profile Switching route
  resolves there. Displays owns the editing profile's display mode and role definitions plus this Mac's
  physical bindings. Menu Bar remains the only editor for the editing profile's display-role icon
  choices. Sync lists the supported synced and always-local
  categories and explains why a reliable synced-device list is unavailable. Focus Border owns
  local per-application corner-radius overrides independently of profile App Rules and Quick Apps;
  removing or converting an App Rule no longer erases that local correction.
- **Profile-tabs implementation:** Replaced the Profile Library master list with a horizontally
  scrolling icon/name tab strip and trailing add tab. The selected profile's prominent identity and
  explicit activation remain separate from a wider automatic-use panel for Default, Game Mode,
  docked, undocked, and exact display contexts. Checked optional rows remove their assignment;
  unchecked rows move the exclusive assignment to the selected profile; Default always keeps an
  owner. Current-display assignment reuses and moves an existing exact topology instead of creating
  a duplicate. The local persistence schema and the edit-target/active-profile boundary are unchanged.
- **Profile-tabs automated evidence:** The complete non-hosted suite passes 782 tests. Focused
  coverage proves legacy routing, merged search, single-owner assignment/removal policy, edit-target
  preservation, and exact-topology reassignment without duplication. Production Profiles renders
  pass in wide and minimum-width compact layouts, Light and Dark appearance, four-profile,
  long-name, and inactive-selected-profile states; comparison with selected direction 3 found no
  remaining structural mismatch after restoring the prominent native icon editor. Release static
  analysis passes, the unsigned Release app builds as universal `x86_64 arm64`, and unsigned
  Stable/Beta DMG smoke verification passes. The signed universal Debug daily candidate
  `4649547db928-dirty` was installed and launched from `/Applications/WindowRanger.app` on
  28 August 2026. Its Apple Development signature, Team ID `44NAD22AK6`, canonical bundle
  identifier, embedded source marker, architectures, running executable path, and byte-for-byte
  match with the just-built executable and debug/preview libraries were verified.
- **Profile-tabs live evidence:** On 28 August 2026, the maintainer reported the signed candidate
  working and supplied active- and inactive-tab screenshots. They confirm that the selected tab,
  active profile, Default/docked/undocked ownership, explicit **Use Profile** action, and exact
  display-setup ownership remain visibly distinct. The first visual direction is accepted as a good
  functional starting point; unspecified refinement is intentionally deferred until the related
  Workspaces direction is explored rather than guessed into this checkpoint.
- **Workspace-tabs implementation:** Replaced the Workspaces master list and compact list/detail
  mode with a horizontally scrollable row of equal visual tabs plus a trailing dashed Add Workspace
  tab. Freeform, Tiled, and Accordion use abstract saved-style miniatures only; selection remains a
  Settings-local UUID and automatically scrolls into view without activating the engine. Wide
  Settings places a 320-point Details panel beside the flexible Layout/Repair column; compact
  Settings stacks the same complete panels beneath the retained tab strip. Drag/drop, drop-to-end,
  a single Duplicate/Delete action row, context-menu Move Left/Right, VoiceOver Move earlier/later,
  CRUD, Home Display, shortcuts, layout
  copy/geometry/reset, collection reset, and active-workspace repair retain their existing store or
  engine owners.
- **Workspace-tabs automated evidence:** The complete non-hosted suite passes 783 tests with zero
  failures. Focused coverage proves UUID selection reconciliation, exact search deep links, profile-
  scoped CRUD/reorder/bindings, layout-specific controls, and saved-style miniature semantics. The
  documented production renderer emits six Light/Dark, wide/minimum-width, conflict, long-name, and
  nine-workspace fixtures by default; combined full and focused comparisons against selected
  direction 2 have no remaining P0-P2 mismatch. Release static analysis passes, the unsigned Release
  app builds as universal `x86_64 arm64`, unsigned Stable/Beta DMG smoke packages verify, and a
  skeptical review found no P0/P1 code regression after its two documentation/render-wiring P2
  findings were corrected. Pointer drag/drop, keyboard traversal, VoiceOver, inactive-profile
  switching, search deep links, and live repair remain signed installed-app validation.
- **Workspace-tabs installed candidate:** With explicit maintainer approval on 28 August 2026,
  signed universal Debug daily candidate `539e0bf945e9-dirty` was installed and relaunched from
  `/Applications/WindowRanger.app` as process `3786`. Strict signature validation, Apple Development
  authority, Team ID `44NAD22AK6`, canonical bundle identifier, embedded dirty source marker,
  `x86_64 arm64` architectures, running executable path, and byte-for-byte equality of the installed
  executable and Debug/preview dylibs with the just-built candidate were verified. The previous
  signed daily remains recoverable at `/Applications/.WindowRanger.previous`; hands-on Workspace
  interaction remains pending.
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
- **Superseded ownership-redistribution automated evidence:** Profiles was limited to the reusable library and
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
- **Status:** Live validation — ordinary-command stale-context correction implemented, reviewed,
  automated-test verified, signed, and installed; maintainer retry pending.
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
- **Ordinary-command regression observed:** During WR-093 live validation, two prompt Command
  Palette selections were rejected as `stale-context`. The second opened on surviving managed
  Claude window `55064:1512` at `09:05:23.184Z`, requested selection 2.56 seconds later, and rejected
  at `09:05:25.833Z` despite no workspace, window, layout, display, or profile change. The controller
  dismissed the palette and ended its external-focus lease before asynchronously requesting the
  validation context, allowing transient nil AX focus to replace the otherwise valid token.
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
  retained. The ordinary-command correction now performs the same fresh revalidation while the
  palette still owns its external anchor, then dismisses and dispatches in the original order;
  placement alone keeps its stronger dispatch-before-dismissal ordering. In-flight validation is
  bound to the originating palette generation so a rapid dismiss/reopen cannot act on a replacement
  presentation. Genuine target changes still fail closed, and Settings retains its direct
  dismissal/opening path.
- **Automated evidence:** The focused 24-test Command Palette suite and complete 758-test non-hosted
  suite pass with focused Quick Action
  availability/navigation, Up-from-first-result entry, nonempty-search hiding, layout-only
  horizontal movement, settled/older-token rebinding,
  changed-window/layout rejection, deferred placement focus restoration, palette-owned transient
  nil-focus coverage, preceding-app-gated Shelf restoration, ordinary-command validation-before-
  dismissal policy, and genuine changed-target rejection, alongside test-isolation, project-
  regeneration, shell-syntax, and diff checks. The
  production-view offscreen snapshots render available, omitted-placement, and placement-only Quick
  Actions, and the expanded Placement Halo follows its row without obscuring the layout control. The
  actual unsigned Debug app target builds successfully as a universal `x86_64 arm64` binary. A
  skeptical read-only review found no blocking ordering, focus, Quick App/Shelf, Settings,
  placement, stale-context, or reentrancy issue after the presentation-generation guard was added.
- **Latest installed correction evidence:** With explicit maintainer approval, the Apple
  Development-signed universal Debug daily candidate `a3de0b817f7f-dirty` was installed at
  `/Applications/WindowRanger.app` and relaunched as PID `60704`. Strict signature validation,
  authority, Team ID `44NAD22AK6`, bundle identifier, `x86_64 arm64` architectures, embedded source
  marker, running path, and CDHash `1a1af9b39a3cf1fd34d03419f411075b1d63ef6c` were verified.
  Diagnostic session `3F32D218-0E53-4E14-82DA-6BDBC3143794` started normally; the previous daily
  build remains recoverable at `/Applications/.WindowRanger.previous` without an `.app` suffix.
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
  General Settings or the setup wizard appears, or WindowRanger becomes active. While either surface
  is visible and access is still missing, it performs a lightweight bounded-frequency trust check so
  an external grant is reflected without closing, reopening, or clicking twice. It must not repeat
  the system prompt.
- **Acceptance:** An injected monitor test proves false-to-true external grants and later revocation
  are reflected without requesting permission. Focused Settings tests, the complete non-hosted
  suite, and an unsigned universal app build pass; signed live validation remains required.
- **Automated evidence:** All 24 focused Utility Settings tests, including deterministic wizard-style
  polling from false to true, pass in the 216-test combined verification. The earlier complete 577-test
  non-hosted suite is superseded by the complete 814-test pass; test isolation, Release static
  analysis, and the unsigned universal Release app build also pass;
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

### WR-090 — Validate Displays have separate Spaces compatibility

- **Type:** Multi-display compatibility validation and diagnostics
- **Priority:** P1
- **Status:** Diagnostic instrumentation implemented; automated verification and signed daily-app
  startup evidence complete; physical multi-display behavior validation remains.
- **Requested:** 27 August 2026, after enabling the default macOS **Displays have separate Spaces**
  setting following the development cycle with it disabled for AeroSpace compatibility.
- **User-observed:** WindowRanger appeared to continue working after the setting was enabled. This is
  not a confirmed compatibility result: AeroSpace documents macOS focus, performance, and native
  Space-transfer failures when Accessibility-driven window movement crosses displays.
- **Smallest useful outcome:** Keep the default macOS setting supported without making native Spaces
  part of WindowRanger's workspace model. Record the setting in startup diagnostics and the bounded
  focused-window support report, then validate the existing parking, restoration, focus, layout,
  full-screen, and reconnect safety paths with real windows on two displays.
- **Acceptance:** With separate Spaces enabled and one ordinary native Space per display, exercise
  Unified and Independent Displays, repeated workspace parking/restoration, same-application windows
  on both displays, Move & Follow to a workspace homed on the other display, Arrange-D workspace
  display movement, native full screen on one display while using WindowRanger on the other, and
  disconnect/reconnect plus sleep/wake. The exact requested window must retain focus without bouncing;
  inactive windows must remain recoverably parked; restored/layout frames must resolve to the intended
  display; and the other display must stay usable during native full screen. Separately switch a native
  Space on one display and confirm WindowRanger fails safely rather than claiming to preserve native
  Space membership. Capture diagnostics after the first mismatch rather than repeatedly moving the
  affected windows.
- **Implemented:** The verbose `session/started` record and schema-v2 focused-window report include
  `displays-have-separate-spaces: true|false`, sampled from AppKit. The value is diagnostic context
  only: it does not enter `DisplaySnapshot`, display-topology identity, persistence, sync, or any
  window-management decision, and WindowRanger does not change the system preference.
- **Automated evidence:** All 11 focused report tests pass, proving both preference values render
  explicitly and the shared startup-field formatter is deterministic. The complete non-hosted quick
  checkpoint passes all 754 tests, and the unsigned universal Debug app builds for `arm64` and
  `x86_64`.
- **Installed evidence (27 August 2026):** The Apple Development-signed universal Debug daily app
  from `develop` at `0561951a20e5-dirty` was installed and relaunched from
  `/Applications/WindowRanger.app`. Its live `session/started` record reported Debug build, two
  displays, Independent Displays mode, and `displays-have-separate-spaces: true`. This proves the
  installed diagnostic path and current system setting only; the acceptance scenarios above remain
  unverified.

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
  border colour, defaulting to light blue (`#3399FF`) independently of the menu bar's white default.
  Existing valid saved colours, including white, are preserved. It monitors only while enabled and draws a nonactivating,
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
- **Default-colour correction:** Focus Border now uses a dedicated light-blue default token rather
  than inheriting the menu-bar highlight default. Missing and malformed focus colours repair to light
  blue; valid stored colours remain unchanged. Menu-bar white and focus-border light blue are covered
  independently by the 216-test combined verification and complete 814-test suite. Release static
  analysis and the unsigned universal Release build pass.
- **Remaining live boundary:** Enable **Highlight the focused window** in General Settings and
  confirm the border tracks real focus, movement, and resizing on both displays without taking focus
  or intercepting clicks. Confirm the light-blue default and custom colours, the Tiled/Accordion edge
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

- **Type:** Resolved product decision
- **Status:** Superseded by Profiles on 25 August 2026; do not implement as a separate feature.
- **Sources:** `docs/future-workspace-systems-decisions.md` and
  `docs/omarchy-inspired-ideas.md`
- **Decision:** A named arrangement was a partial Profile: it stored application-to-workspace
  assignments and workspace layouts through a second persistence, preview, and activation path.
  Profiles already own named reusable workspaces, Application Rules, layouts, display roles, and
  manual/automatic activation. The narrower arrangement semantics did not justify the overlapping
  concept or Settings surface.
- **Result:** The uncommitted experiment was removed before entering the profile schema. Profile
  activation improvements belong in WR-088. A future temporary group must demonstrate a distinct
  session-only interaction rather than reintroducing a partial Profile under another name.

### WR-009 — Optional workspace/stage overview

- **Type:** Feature research
- **Status:** Needs decision
- **Source:** `docs/future-workspace-systems-decisions.md`
- **Decision:** Whether metadata-only is valuable first; whether thumbnails justify Screen
  Recording permission; placeholder/cache privacy; panel scope; click and drag semantics.

### WR-010 — Tiled layout templates and builder

- **Type:** Feature research
- **Status:** Needs decision — narrowed on 25 August 2026 to topology templates inside Tiled only.
- **Sources:** `docs/future-workspace-systems-decisions.md` and
  `docs/omarchy-inspired-ideas.md`
- **Concept:** A Tiled workspace may select a built-in or custom normalized split topology, such as
  four equal windows in a 2x2 grid or one large window on the left with two stacked on the right. A
  visual builder edits semantic slots and ratios, not application identities or live window IDs. Applying
  a template assigns the workspace's current eligible windows deterministically by layout order.
- **Recommended first boundary:** Tiled only; ship a small built-in template set; require the exact
  participant count and disable application with a clear count mismatch rather than guessing.
  A custom topology is created through an offscreen builder preview and embedded in that workspace,
  with no separate named template library. Built-in selection likewise copies its topology into the
  workspace. WR-087 remains the simple way to copy the resulting layout to another workspace.
- **Decisions required:** Confirm eligible-window counting rather than one-window-per-app; choose the
  built-in templates and names; define the persisted normalized split-tree schema; exact-count versus
  adaptive behavior after a window opens/closes; deterministic slot ordering and manual reassignment;
  minimum sizes, aspect-ratio/display changes, Undo, migration, sync/import bounds, and builder
  accessibility.

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
- **Status:** In progress for the 1.0.0 candidate. On 30 August 2026, the combined CLI,
  updater-repair, and Homebrew-preparation source passed the complete 857-test non-hosted suite,
  static analysis, an unsigned universal Release app/CLI build, and both Stable and Beta DMG
  construction and verification under stable Xcode 26.6. The same checkpoint also passed under
  Xcode 27 beta as compatibility evidence. This was a dirty topic-branch preparation check, not the
  required clean, committed, exact-release build; the Stable checkpoint must be repeated after
  build 12 is allocated on `develop` and the reviewed contents reach `main`.
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
- **Status:** In progress. With explicit maintainer approval on 30 August 2026, the Beta 10 updater
  repair, public 1.0.0 and 1.0.1 Stable releases, combined Stable/Beta feed, and Stable Homebrew tap
  were published. The packaged Beta 7-to-Beta-10 updater path, exact Stable DMG installations, and
  Homebrew 1.0.0-to-1.0.1 upgrade passed live validation. Remaining updater and Homebrew validation
  work is recorded below; each later release remains separately held until explicitly approved.
- **Decided:** Stable (`main`), Beta (`release/*`), and Dev (`develop`) channels using the documented
  Gitflow-style promotion model. Sparkle is the updater for the default Stable and
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
- **User-observed updater failure:** On 29 August 2026, a second Mac could not update to Beta 10 and
  eventually reported an updater error. Read-only investigation on 30 August confirmed that Beta
  7–10 all contain the intended HTTPS feed URL, Beta channel, incrementing builds 8–11, the same
  public EdDSA key, and valid Developer ID signatures. The live `appcast.xml` and every expected
  `/updates/WindowRanger-*.zip` endpoint return HTTP 404. The GitHub releases and exact ZIP assets
  are public, but the separately gated Sparkle feed was never generated and deployed. This is a
  missing publication checkpoint, not evidence of an app-side polling fault.
- **Repair implementation:** Feed preflight now requires the latest public GitHub release to be
  `published` in the central ledger, while distribution builds still require an active `allocated`
  row. It verifies the local ZIP against the checksum attached to that public release before any
  Keychain signing access, and `--preflight` exercises the complete uncredentialed boundary. This
  removes the earlier deadlock where the documented post-release feed step rejected every already
  published build. The generator now defaults to WindowRanger's matching project-specific Keychain
  account and structurally accepts Sparkle's recommended top-level build version as well as retained
  legacy enclosure attributes.
- **First-feed publication evidence:** With explicit maintainer approval, Beta 10 build 11 was
  signed using the matching project-specific Keychain key and deployed with its exact public ZIP
  through Cloudflare version `a5cb408a-5341-486b-b2f5-33658e30c80a` on 30 August 2026. The live
  appcast and archive return HTTP 200 with the intended XML/ZIP content types and cache policy. The
  downloaded appcast is well-formed, selects build 11 on the `beta` channel, and retains SHA-256
  `8aaa31d3b734408d36c7de13f7fa38f1e82624b46d280c41595750f4d4d1aa48`. Its downloaded
  16,003,813-byte archive matches the immutable GitHub release SHA-256
  `de8b2a282780d128358855dfcdf83934f40e4eac493805bc2c36ef7d71082fe6`, and Sparkle's
  `sign_update --verify` accepts the enclosure signature. This establishes feed publication, not
  an installed-app upgrade result.
- **Packaged upgrade evidence:** On 30 August 2026, the maintainer installed the public packaged
  Beta 7 baseline, used its in-app updater against the newly published feed, and confirmed that the
  upgrade to Beta 10 completed successfully and the resulting app worked normally.
- **Remaining scope:** Back up the release EdDSA key through the maintainer's secure credential
  process; validate cancellation/failure/Beta-to-Stable/rollback behavior; then decide when
  automatic checking can default on. Update/rollback failure handling and the Homebrew install,
  upgrade, uninstall, `--zap`, architecture, and macOS privacy-permission matrix also remain.
- **Homebrew preparation:** Stable-only Cask generation now verifies the local DMG checksum and can
  require a public, immutable, non-prerelease GitHub release whose DMG is byte-identical. The
  generated Cask declares Sparkle coexistence, macOS 14, ordinary uninstall that preserves user
  configuration, and an explicit local-only `--zap` scope. Deterministic fixtures reject Beta,
  malformed or mismatched artifacts, prerelease metadata, silent overwrite, and failed-publication
  mutation. The public v1 artifact generated the exact Cask successfully. Homebrew 6 audit found
  and prompted removal of its deprecated `verified:` URL parameter before publication; the
  deterministic workflow now rejects that regression. The main Homebrew Cask still fails the
  documented notability threshold, so the separately approved `AppRanger/homebrew-tap` route is
  used instead.
- **1.0.0 candidate preparation:** The first Stable release notes are published at
  `docs/releases/v1.0.0.md`. The CLI and release-tooling changes were integrated into `develop` by
  PR #77, build 12 is allocated as the first Stable candidate, and exact release source was promoted
  to `main` through PR #79 after its protected release checks passed. The first credentialed build
  exposed and PR #80 fixed the new CLI target being installed as a second archive product; PR #81
  synced the embedded-only fix and deterministic `SKIP_INSTALL` guard back to `develop`.
- **1.0.0 candidate evidence:** Stable Xcode 26.6 built candidate `1.0.0` build 12 from exact `main`
  commit `9a5c26e9b30226c86b4e39bf7e32305a30c6524d` after all 857 non-hosted tests and static analysis
  passed. The app and embedded CLI are universal `arm64`/`x86_64`, carry the expected Developer ID
  team and Hardened Runtime, and pass strict nested-signature verification. Apple accepted the app
  (`f63dcde6-be8f-448e-be5c-8cfc7348bccf`) and DMG
  (`d4db64d4-6049-4630-be12-bdea055bf08f`) notarizations with zero logged issues; both tickets are
  stapled and Gatekeeper accepts both artifacts. The independently verified SHA-256 values are
  `9820099f19240d64b500cdd5e4121ec8ea6f34d53cdb6c6313d8cfebd8711d25` for the ZIP and
  `387f50a42a542729f27efb6c473e771568bb0701e049e71d3c6210ff0215f604` for the DMG. Exact packaged
  installation/live validation was completed by the maintainer without an observed issue.
- **1.0.0 GitHub publication:** The protected annotated tag `v1.0.0` resolves to exact candidate
  commit `9a5c26e9b30226c86b4e39bf7e32305a30c6524d`. The public non-prerelease GitHub release contains
  the expected DMG, ZIP, both checksum files, and provenance manifest; all five downloaded assets
  round-trip verified against the immutable tag and local candidate. Build 12 is therefore marked
  `published` in the central ledger.
- **1.0.1 GitHub publication:** The protected annotated tag `v1.0.1` resolves to exact `main` commit
  `22049ae01d9ade88fd9d0eb7eb5ac8a0cfb8838b`. Stable Xcode 26.6 produced universal build 13;
  Apple accepted both app and DMG notarizations with zero issues, and the signed installed CLI peer
  correction passed the live checks recorded under WR-074. The public non-prerelease release's five
  assets round-trip verified against SHA-256
  `781715f5ef1deb63534553c44c42eb5048e758a867fb2d5525d9e5938091909a` for the ZIP and
  `6bf88eec14cf28d4dae03b3d27ddbf7898b0c2e1d505e57c9cb05f13c7a31f90` for the DMG. Build 13 is
  therefore marked `published` in the central ledger. Its signed-feed and Homebrew publication
  evidence is recorded below.
- **1.0.0 feed publication:** The signed feed retaining Beta 10 build 11 and adding Stable 1.0.0
  build 12 plus its delta was deployed through Cloudflare version
  `1f3fc001-8180-4255-ae77-b71cefd1c16c`. The live appcast has SHA-256
  `8d54a8db20539ec56119af39e4281da25217b533987536182b6ca7dbdeb47c09`; all three downloaded
  payloads match the deployment source, and Sparkle accepts every live enclosure and delta
  signature. The XML, ZIP, and cache headers were also checked at their public endpoints.
- **1.0.1 feed publication:** Website commit
  `d66e68cb9684e18446b32cd08f034456542ae997` published the feed retaining builds 11 and 12 and
  adding Stable 1.0.1 build 13 with deltas from both retained builds. Cloudflare deployment
  `24e5fe44-77e2-4320-bcb9-2203e3ac014f` serves the exact appcast SHA-256
  `56cf7a07cfa88bc041bd7f241e5de341a1fd397c87de81f5e68e93b59e919453` from both domains. All six
  downloaded ZIP/delta payloads match their publication-source hashes, and Sparkle accepts every
  live enclosure and delta signature. The public homepage also links the 1.0.1 Stable release.
- **Homebrew publication:** The public
  [`AppRanger/homebrew-tap`](https://github.com/AppRanger/homebrew-tap) contains the exact Stable
  1.0.0 Cask with SHA-256
  `b1403c2263c5185f053df1ccbc4866e5357e066b64cf796a1246df6f35461363`. After a fresh public tap,
  Homebrew 6 style and strict online audit passed, and `brew info` resolved version 1.0.0, the macOS
  14 minimum, automatic-update declaration, and application artifact. The supported install command
  is `brew install --cask appranger/tap/windowranger`.
- **Homebrew live evidence:** On 30 August 2026, Homebrew 6 installed the public Cask on an Apple
  Silicon Mac running macOS 27. The resulting 1.0.0 build 12 has the expected bundle identifier,
  Team ID, notarized Developer ID acceptance, stapled ticket, strict nested signature, and universal
  app/helper architectures. Reinstall preserved the preference domain byte-for-byte. Ordinary
  uninstall removed the app while retaining all four existing declared local-state locations and
  byte-identical preferences; reinstall retained them again. Explicit `--zap` removed all nine
  declared current/legacy paths while leaving shell-startup and CLI PATH-link state unchanged. A
  private backup then restored the four paths that existed before the test and the preference domain
  byte-for-byte before final Cask reinstall and launch. Homebrew's first ordinary uninstall also
  auto-removed an unrelated unneeded `go@1.26` formula; it was restored at the same 1.26.7 version
  and autoremove was explicitly disabled for the zap test. The Homebrew-managed app is installed and
  running. Intel, a real later-version Homebrew/Sparkle upgrade in both orders, Settings PATH UI,
  and macOS privacy-permission retention remain live validation. The separately tracked WR-074 CLI
  peer-path failure prevents claiming packaged CLI runtime acceptance for 1.0.0.
- **1.0.1 Homebrew publication and upgrade evidence:** Tap commit
  `962dc4015cd742ea1a292e97b8b7dcd89e6863de` publishes the generated 1.0.1 Cask for the exact
  notarized release DMG SHA-256
  `6bf88eec14cf28d4dae03b3d27ddbf7898b0c2e1d505e57c9cb05f13c7a31f90`. Homebrew 6 style and
  strict online audit passed. On the same Apple Silicon/macOS 27 Mac, a genuine 1.0.0 build 12 app
  and receipt upgraded through Homebrew to 1.0.1 build 13. The installed app passed strict nested
  signature, notarized Gatekeeper, relaunch, signed CLI read/configuration/skill, and eight-client
  concurrency checks. Configuration values were preserved; only request/revision metadata and
  collection serialization ordering changed across relaunch. This proves the Homebrew-forward
  upgrade direction. Sparkle-first/Homebrew coexistence, Intel, Settings PATH UI, and privacy
  permission retention remain live validation.
- **Gate:** Each later release still requires explicit maintainer approval.

## Done

### WR-107 — Publish WindowRanger 0.1.0 Beta 10

- **Result:** Published
  [`v0.1.0-beta.10`](https://github.com/AppRanger/windowranger/releases/tag/v0.1.0-beta.10) as a
  GitHub prerelease on 29 August 2026. The protected annotated tag points to exact release commit
  `ea9f330bdeb1bb195b34348e766b8785d4a28805`; central `develop` owns build `11`, and the
  [release-branch CI run](https://github.com/AppRanger/windowranger/actions/runs/33252397850) passed
  814 tests, static analysis, an unsigned universal Release build, and both DMG smoke layouts.
- **Distribution evidence:** Stable Xcode 26.6 reproduced the 814-test pass and static analysis,
  then built the Developer ID-signed universal `arm64`/`x86_64` archive. Apple accepted the app
  (`a05ef8f3-b827-403a-8bcd-d0b886b93db4`) and DMG
  (`e58bbb78-03e0-4f22-b154-45716aba5316`) notarizations with zero issues; both stapled artifacts
  passed validation and Gatekeeper. The five public assets round-tripped against the tag, build,
  channel, provenance, and SHA-256 values `516e59e7ae9655cb867ce7315313b30f40c114a2a644b1f3820f1c3a63ee1df8`
  (DMG) and `de8b2a282780d128358855dfcdf83934f40e4eac493805bc2c36ef7d71082fe6`
  (ZIP).
- **Validation boundary:** The documented repeat-Beta path applied because the release contained no
  packaging, signing, entitlement, identity, updater, migration, or minimum-system change. The
  maintainer accepted the same signed-daily product code and the grouped menu-bar composition also
  passed macOS 26 UTM acceptance, so a second packaged replacement install was not required. The
  maintainer's Mac still runs the signed daily rather than packaged Beta 10. Public appcast
  generation, website deployment, exact packaged-artifact installation, and the outstanding
  physical multi-display and clean-machine matrices remain outside this checkpoint.

### WR-103 — Publish WindowRanger 0.1.0 Beta 9

- **Result:** Published
  [`v0.1.0-beta.9`](https://github.com/AppRanger/windowranger/releases/tag/v0.1.0-beta.9) as a
  GitHub prerelease on 29 August 2026. The protected annotated tag points to exact release commit
  `ff2e38d80d864a7c767479f0e98ad02617b196be`; central `develop` owns build `10`, and the
  [release-branch CI run](https://github.com/AppRanger/windowranger/actions/runs/33245036560) passed
  814 tests, static analysis, an unsigned universal Release build, and both DMG smoke layouts.
- **Distribution evidence:** Stable Xcode 26.6 reproduced the 814-test pass and static analysis,
  then built the Developer ID-signed universal `arm64`/`x86_64` archive. Apple accepted the app
  (`69987b7b-5297-4f92-b2e8-a3c77439c051`) and DMG
  (`10a1268d-072b-4334-b56b-2c8fff18415b`) notarizations with zero issues; both stapled artifacts
  passed validation and Gatekeeper. The five public assets round-tripped against the tag, build,
  channel, provenance, and SHA-256 values `a2bf886e7d96620a465b39750fd56e1ff2371c123c8a4e473b5e1e646ba8b4eb`
  (DMG) and `fa6064179ff41c072a6bcec62ffc4cc68c7689f9eb77cca59ea39c232b347f0e`
  (ZIP).
- **Validation boundary:** The maintainer's Mac still runs signed daily revision
  `539e0bf945e9-dirty`, not the packaged Beta. Exact packaged-artifact installation and the new-Mac
  first-enable iCloud path remain live validation, together with the latest onboarding permission
  refresh, setup-wizard Space behavior, fifth-workspace shortcuts, and optional captured previews.
  Public appcast generation and website deployment were intentionally outside this checkpoint.

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
  documented cosmetic macOS 27 beta limitation rather than a reason to reintroduce unsafe routing;
  it was later reopened for a safe detached-menu correction under WR-109.

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
