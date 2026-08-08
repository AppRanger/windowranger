# Window Manager

A small, native macOS virtual-workspace manager built around one workflow rather than a general-purpose command language.

## Current feature set

- Three native, display-aware menu-bar presentations: Compact by default, Medium chips, or a Full display-grouped workspace strip.
- A standard menu from the primary app item with Settings and a graceful Quit command; the primary item never switches workspaces.
- Virtual workspaces that remember window membership and the active workspace across app restarts.
- Named reusable profiles with local manual/automatic selection, dock and exact-topology triggers, synced abstract display roles, and per-Mac monitor bindings.
- Switching parks windows from inactive workspaces at the edge of the desktop and restores their previous frames when returning.
- Workspace switches restore the destination before parking the source, touch only those two workspaces, issue position-only Accessibility writes, and suppress participating apps' own move animation for the duration of each batch.
- Global shortcuts matching the current AeroSpace configuration.
- Native sidebar-based, searchable Settings for profiles, workspaces, displays, layouts, app rules, shortcuts, the command wheel, permissions, startup, recovery, and iCloud sync.
- Two multiple-display modes: unified switching across all displays, or independent active workspaces assigned per display.
- Workspace-local window focus cycling with `Option-[` and `Option-]`, wrapping without selecting parked windows.
- Automatic workspace following when a managed window is focused through the Dock or another macOS route.
- Per-workspace Freeform, Tiled, and Accordion layouts with migration-safe persistence, automatic or explicit orientation, gaps, outer padding, Accordion overlap, and stable ordering/weights.
- A configurable two-level contextual command wheel that shows only valid actions for the focused window, active workspace, layout, and interaction display.
- Extensible per-application rules for workspace routing, visibility on every workspace, layout exclusion, and conservative secondary-window floating.
- Per-window floating overrides that retain workspace membership while opting out of Tiled and Accordion.
- Directional focus/reorder, smart resize, workspace reset, and workspace-to-display commands.
- Portable display-home matching using runtime UUID first and conservative hardware fingerprints on reconnect.
- Optional focus-following when moving a window, opt-in hidden-app compatibility, and an explicit native launch-at-login control.
- No native macOS Spaces integration.

Default shortcuts:

| Action | Shortcut |
| --- | --- |
| Switch to workspace | Control-Option-`workspace key` |
| Move focused window | Option-Command-`workspace key` |
| Previous / next workspace | Control-Option-`[` / `]` |
| Switch back and forth | Control-Option-Tab |
| Previous / next window | Option-`[` / `]` |
| Select Accordion / Tiled | Option-`,` / `.` |
| Toggle focused window floating | Control-Option-F |
| Focus left / down / up / right | Option-H / J / K / L |
| Reorder left / down / up / right | Control-Option-Left / Down / Up / Right |
| Smart resize smaller / larger | Control-Option-`-` / `=` |
| Move current workspace to next display | Option-Shift-Tab |
| Open contextual command wheel | Control-Option-Space (configurable) |

## Build

Generate the Xcode project:

```sh
xcodegen generate
```

Open `WindowManager.xcodeproj`, select a Development Team, and run the `WindowManager` scheme. The app requests Accessibility access on first launch. iCloud key-value sync requires a signed build with the iCloud capability available to the selected team.

Quit AeroSpace before testing the global shortcuts: macOS lets only one app register a given Carbon hotkey, and the defaults intentionally overlap your AeroSpace bindings.

For side-effect-free automated tests:

```sh
./scripts/verify-test-isolation.sh
xcodebuild -project WindowManager.xcodeproj -scheme WindowManager -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

The unit-test bundle is deliberately non-hosted: it compiles the shared sources directly and
excludes `AppDelegate`, so tests never launch WindowManager, request Accessibility access, register
hotkeys, manage live windows, or build/register a `WindowManager.app`. Do not give automated tests a
temporary `-derivedDataPath` and do not add the app target back to the scheme's Test build action.
Xcode's macOS app build step registers every built app with LaunchServices; current Xcode provides no
supported per-build opt-out. App builds should therefore use the normal Xcode DerivedData location,
while background verification should invoke the isolated Test action above.

The three menu-bar components also have an opt-in offscreen Retina fixture built from the production
views. It runs in the same non-hosted test bundle and does not start the app or Accessibility paths:

```sh
./scripts/render-menu-bar-previews.sh /path/to/output-directory
```

The current selected-reference review and durable output paths are recorded in `design-qa.md`.

The scheme runs as **Debug** from Xcode and archives as **Release**. Both configurations keep the
same signed `com.chris.WindowManager` identity, so Debug does not create a second Accessibility
client. Debug app runs write structured JSON Lines diagnostics to
`~/Library/Logs/com.chris.WindowManager/diagnostics.jsonl`; the file rotates at 1 MB and retains two
1 MB backups. Release builds do not create this verbose file. Unit tests use memory or no-op loggers
and never write there.

The Debug app menu identifies the build and provides **Copy Recent Diagnostics** (a bounded recent
excerpt with its privacy notice) and **Reveal Diagnostics File**. Diagnostics contain action/session
IDs, bundle identifiers, internal window/workspace/display IDs, layout decisions, frames, and AX
success/failure results. They do not collect window titles, document names, URLs, typed content,
full file paths, or window contents.

Copied diagnostics are line-safe and action-aware: the latest correlated hotkeys and their resulting
focus/layout events are retained separately from the noisy file tail, so ordinary background polling
cannot evict the trigger. Background layout enforcement is input-driven rather than timer-driven;
an unchanged poll performs no layout writes, and an app that rejects a target frame is retried only
after a relevant geometry input changes or the user explicitly requests the layout again.

## Profiles

A profile is a reusable configuration, never a snapshot of open windows. Each profile contains its
ordered workspace definitions and keys, per-workspace layout and geometry, Unified or Independent
Displays mode, abstract display roles and workspace-role homes, and the complete app-rule collection
including paused rules. Exact open-window IDs, workspace membership, frames, and focus remain local
session state and are not copied into a profile.

Profile definitions are stored as one versioned value and sync atomically through iCloud when sync is
enabled. This Mac keeps its active profile, manual pin, automatic trigger mappings, per-profile active
workspace state, conservative monitor fingerprints, and role-to-monitor bindings locally. A missing,
disconnected, or ambiguous role safely falls back without rewriting the synced role assignment.

Automatic selection resolves in a fixed order: a manual pin; an exact known display topology; a
generic docked or undocked rule on portable Macs; then this Mac's default profile. A manual selection
cannot be cleared by wake, timers, or later display events—choose **Resume Automatic** in Profiles
Settings or the app menu to release it. A portable Mac with only its built-in display is undocked; a
portable Mac with an external display is docked. Desktop Macs skip that generic distinction.

The Profiles Settings pane can create a profile from the current reusable configuration, duplicate,
rename, select, and safely delete profiles; it also manages this Mac's triggers and physical role
bindings. Switching profiles first recovers eligible managed windows to meaningful visible frames,
then applies the destination workspaces, display state, and app rules. Still-open windows are routed
by destination app rules or conservatively placed on an active destination workspace rather than
retaining membership from the old profile. Ignored panels and temporarily unsafe minimized or
full-screen windows remain untouched. The app menu shows the active profile and its selection reason
and provides quick switching without making the primary menu-bar item a workspace action.

On the first profile-capable launch, the existing private installation's reusable configuration is
backed up, converted into **Current Setup**, saved in the new profile format, and decoded back for
verification before the old settings keys and backup are removed. Profile-backed storage is then the
sole configuration authority.

## Contextual command wheel

The command wheel is a global interaction preference, not part of a profile. Its shortcut uses the
same recorder, conflict detection, and reset behavior as other global commands, with
**Control-Option-Space** as the migration-safe default. **Press to Toggle** preserves the original
interaction. **Hold to Show** waits for the configured 0.15–1.0 second threshold, captures one exact
window/workspace/display context, and commits the highlighted command on release; a short tap,
Escape, stale context, or release without a valid selection cancels safely. The initial Carbon-based
recorder requires a non-modifier key, so modifier-only and Fn-only triggers are intentionally not
supported without a future, separately reviewed event-input design.

The wheel definition is versioned, data-driven, global/iCloud-synced, and limited to two levels. It
stores only an ordered catalogue of top-level type IDs. Each provider resolves an optional primary
action and generated outer-ring children from one immutable runtime context; the renderer and
Settings editor contain no workspace/profile/layout business rules. Every visible inner item gets an
equal wedge around the full circle, and invalid items or empty groups close cleanly without dead
slots. The built-in order is:

1. **Move to Space** — generated valid destinations; send-only by default, with Option for the
   existing one-shot Move & Follow action.
2. **Resize / Place** — Tiled gets eight compass placements with an exact no-write preview;
   Accordion gets truthful Smaller/Larger actions; Freeform omits the item.
3. **Go to Space** — generated valid workspace destinations, excluding the current no-op.
4. **Next Space** — direct action.
5. **Previous Space** — direct action.
6. **Profiles** — generated reusable profiles and Resume Automatic only when meaningful.
7. **Reset Windows in Space** — direct, current-workspace recovery.
8. **Reset All Windows** — direct, explicitly broad recovery using the established safe reset path.
9. **Layout Type** — inner click cycles; outer choices select or reapply Freeform, Tiled, and
   Accordion.

Command Wheel Settings keeps the shortcut and Press/Hold controls, a code-native two-ring preview,
and the ordered top-level catalogue editor together. Items can be added, hidden, and drag-reordered;
their children are generated automatically and are never manually persisted. Edits participate in
native Undo. Repair removes unresolved references and Reset restores the built-in definition, so a
damaged or empty saved definition cannot make the wheel inaccessible.

The visual and hold-interaction design was informed by the [official Loop repository](https://github.com/MrKai77/Loop),
the [BetterStage Snap Wheel guide](https://betterstage.app/docs/snap-wheel), and BetterStage's
[official settings reference](https://betterstage.app/docs/settings-reference). These are design
references only: WindowManager uses its own contextual command catalogue, geometry, native material
treatment, accessibility semantics, and profile boundary rather than copying their branding, assets,
or snap-centric command layouts.

The complete interaction/provider contract is documented in
[Contextual Radial Menu](docs/radial-menu-design.md). Its subordinate
[Radial Tiled Placement](docs/radial-tiled-placement.md) contract defines compass-style choices that
preview deterministic tiled-tree transformations without Accessibility writes, then commit the
validated proposal through one normal layout transaction. Tree state remains local to the current
WindowServer session and never becomes synced profile configuration.

## Current behaviour and limits

Window membership, original positions, per-window floating overrides, and the active workspace are saved locally in `~/Library/Caches/com.chris.WindowManager/workspace-state.json` for the active profile. On a normal quit, the state is saved before every managed window is made visible again. On the next launch, exact window-ID and app-bundle matches are returned only when the saved profile and WindowServer session remain valid; the previously active workspace is shown, and inactive workspaces are parked again.

Window IDs are only trusted inside the same WindowServer session. After logout, reboot, or a WindowServer restart, stale assignments are ignored rather than guessed. If a crash or Xcode Stop leaves a window parked, the continuously saved state normally reconstructs it on the next launch; an unmatched parked window is instead recovered to the main display.

Sleep/wake recovery is lifecycle-driven rather than left to the background window poll. Before sleep,
the app persists workspace intent and invalidates delayed focus/layout work. Wake, screen-wake, user-
session activation, and display-topology notifications coalesce into one generation: portable monitor
homes resolve first, fresh Accessibility window lists are acquired next, and visibility/layout is
applied once from the stable snapshot. A changed topology or temporarily incomplete AX enumeration
gets at most two bounded retries. Minimized, full-screen, ignored, disappeared, or still-unresponsive
windows are left untouched rather than being moved from stale AX elements. A changed WindowServer
session keeps the active workspace intent but discards unsafe exact window IDs.

Lifecycle wiring follows Apple's documented notification centers and boundaries:
[NSWorkspace willSleep](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification),
[didWake](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification),
[sessionDidBecomeActive](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidbecomeactivenotification),
and AppKit's main-actor
[didChangeScreenParameters](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification).

Inactive windows are parked at the lower-right desktop edge because public macOS APIs do not provide a per-window hide operation. Unified mode keeps one active workspace across every display. Independent Displays mode gives each display its own active workspace and assigns each workspace an abstract display-role home. Role assignments sync with their profile, while this Mac retains the physical UUID/fingerprint binding locally; a disconnected role falls back safely and returns on reconnect. The Settings recovery button restores every tracked window; if a prior crash or force-stop left only a parked coordinate to recover, it centers that window on the main display without resizing it. A normal app quit performs the same cleanup. Animation suppression is temporary and app-scoped; it does not change macOS system animation or Accessibility settings.

Layout is selected independently for each workspace. **Freeform** preserves manual window frames and stops automatic positioning or resizing; WindowManager still manages workspace visibility, focus, persistence, display assignment, and quit/wake recovery. Tiled is a deliberately flat, non-overlapping split with stable order and per-window weight. Accordion follows the current AeroSpace-style overlapping stack with the focused window promoted to its primary pane. Both automatic layouts can resolve orientation from the display shape or use an explicit horizontal/vertical direction, with per-workspace inner gaps, outer screen padding, and configurable Accordion visible-edge padding. In Unified mode each display's windows are laid out separately according to saved display affinity; Independent Displays mode lays the workspace out only on its assigned display. The persisted raw value remains `none`, so existing and legacy saved definitions migrate without changing behavior.

Control-Option-F toggles only the focused managed window between Floating and the workspace layout, matching the existing AeroSpace binding. Enabling Floating captures the current frame and leaves the window in its workspace while the remaining windows reflow; disabling it immediately returns the window to Tiled or Accordion. The override is restored only when the exact window ID and bundle identifier still match within the same WindowServer session, and is discarded with other stale window state. An app-level layout-exclusion rule is authoritative: the shortcut makes no contradictory override and the menu-bar icon briefly explains why.

Dialogs use the same managed workspace membership, visibility, focus, display affinity, persistence, and quit recovery as normal windows, but high-confidence dialogs float automatically so they do not distort Tiled or Accordion. High-confidence signals are an Accessibility sheet role, a system-dialog subrole, or a layer-0 dialog/floating-window subrole corroborated by reliable window-control metadata. Ambiguous dialog-like windows remain in the layout; a missing or failed Accessibility read is never treated as positive evidence. Verified nonzero-layer Codex transient panels remain ignored entirely.

Layout precedence is explicit and deterministic: an app-level **Do not include in Tiled or Accordion** rule wins first; a per-window Control-Option-F choice wins over automatic behavior; verified dialog floating applies next; an opt-in per-app **Float detected dialogs and secondary windows** rule can also float conservatively ambiguous dialog-like metadata; otherwise a normal window participates in layout. The secondary-window rule never uses titles and never infers from size or non-resizability alone. Pressing Control-Option-F on an automatically floated window forces it into the current layout, and pressing it again makes it explicitly floating. Only the explicit per-window choice persists for the exact window ID within the current WindowServer session. Automatic classification is reevaluated from live metadata and is never copied onto a newly created window ID.

Application Rules are selected from installed or currently running apps and are stored by bundle identifier rather than file path. A workspace assignment routes both new and previously managed windows to that workspace; in Independent Displays mode it also follows that workspace's display home. Keep on all workspaces takes precedence over assignment, prevents parking, and preserves the window's existing display affinity. Layout exclusion leaves the app's windows at their current frames while the remaining windows participate in Tiled or Accordion. Secondary-window floating is narrower and preserves ordinary document-window layout participation. No rules are created during migration, so existing behavior is unchanged until a rule is added.

Rules can be paused without deleting their saved actions. Rule edits apply immediately to managed windows and participate in the Settings window's normal Command-Z Undo chain. Disabled rules remain persisted and synced, but resolve to no behavior until resumed.

Existing global command shortcuts can be recorded and reset in Settings. The recorder temporarily suspends WindowManager's Carbon registrations, rejects bare typing and conflicts with workspace, command-wheel, or other command bindings, and preserves every established default until the user explicitly changes it. Workspace-specific switch/move bindings remain configured with the workspace definitions; no default chord was invented for selecting Freeform.

Moving a focused window is send-only by default: the source workspace remains active and focus moves to the next eligible visible window on the same interaction display. **Focus follows moved window** is opt-in in General Settings, and the command wheel always offers a one-shot **Move & Follow** action. If no local source window remains, internal focus state is cleared rather than selecting a parked or other-display fallback.

Menu-bar presentation is selected in General Settings and syncs with other global settings through iCloud when enabled. **Compact** (the migration-safe default) uses an overlapping-window app symbol plus one tiny screen/workspace signal per connected logical display. **Medium** uses an equal-height chip for every display's active workspace. In both modes the interaction display receives a restrained accent, every indicator is informational, and the entire status component opens the app menu. **Full** uses the same single stable status component, with a visually distinct app-menu target followed by lightweight display groups containing explicit workspace buttons; only those buttons switch workspaces. Independent Displays shows each connected display's own active workspace simultaneously, while Unified uses one combined-displays signal and one workspace set.

Long names remain available to tooltips and VoiceOver while visible labels are bounded. Under severe notch or menu-bar pressure, Full first compacts labels, then hides inactive buttons deterministically behind a disclosed `+N` overflow while keeping every connected display and its active workspace visible. Missing display homes are not shown as connected and are never rewritten by this presentation layer. Existing private-install values migrate once: Compact and Icon Only become Compact, Active Workspace Label becomes Medium, and Full Workspace Strip becomes Full.

The choices deliberately combine a few proven patterns rather than copying a single product: AeroSpace exposes the current workspace in its tray icon, AeroSpork renders active per-monitor workspace chips, Loop uses a compact icon-led menu, and BetterStage allows selectable status content. WindowManager keeps one always-accessible primary menu target in every mode so presentation choices cannot strand Settings or Quit. The production component is owned by one persistent AppKit status item; changing Compact, Medium, or Full reconfigures that item instead of disconnecting and recreating status scenes.

High-frequency command feedback uses one centered, click-through nonactivating overlay rather than a status-item popover or notification banner. It follows the resolved interaction display, never becomes key or main, coalesces rapid updates, and cleans itself up across display changes, sleep, and quit. Debug diagnostics record the overlay lifecycle and display decision without recording its message text. In Debug Settings, **Window Admission** can also show the engine's existing privacy-safe managed/floating/deferred/ignored classifications and reasons; refreshing that view does not re-enumerate, move, resize, or focus windows.

Switching to a workspace focuses an eligible window in that workspace on the resolved destination display. In Independent Displays mode, the workspace's logical home chooses which active-workspace slot changes, while its currently connected home or safe physical fallback chooses where focus is attempted; other displays remain untouched. Local focus history is preferred, then deterministic visible local order. An empty workspace does not focus a parked window or steal focus from another display. Unified mode retains the actual interaction display rather than defaulting to the main display.

Physical display-role bindings are local to each Mac. The app first matches the stable runtime display UUID, then may use a portable vendor/model/serial fingerprint when reconnecting. If multiple identical displays match, it does not guess; the workspace's synced abstract home remains intact while its physical placement falls back safely until the user chooses a binding. Option-Shift-Tab swaps the current Independent Displays workspace onto the next connected role while keeping both displays' active-workspace invariants valid.

**Open at login** uses macOS's native login-item service and changes only after an explicit Settings toggle. **Automatically unhide applications when focusing their windows** is an opt-in compatibility setting, off by default, and throttles duplicate attempts to avoid activation loops. Automated tests inject substitutes and never alter the live login-item state.

Use the primary app menu's **Quit WindowManager** command when testing quit recovery. Xcode's Stop button terminates the debug process immediately, so macOS does not give the app an opportunity to run synchronous cleanup; continuously saved state is used to recover on the next launch instead.

## Reproducing a cross-display focus jump

1. Gracefully quit the old build with the primary app menu's **Quit WindowManager**.
2. In Xcode, keep the `WindowManager` scheme on its normal Debug Run configuration and click Run.
3. Focus a managed window on the second display, then use Option-`[` / Option-`]` to cycle windows.
4. With the second-display window focused, use Option-`,` or Option-`.` to change its workspace layout.
5. If focus jumps to the main display, stop after one occurrence and choose **Copy Recent Diagnostics** from the primary app menu. The log can instead be inspected directly with **Reveal Diagnostics File**.

## Retesting sleep/wake recovery

1. Gracefully quit the currently running old build with the primary app menu's **Quit WindowManager**.
2. In Xcode, select the normal `WindowManager` scheme and Debug Run configuration, then click Run.
3. In Unified mode, put windows from visible and inactive workspaces on both displays, sleep the Mac,
   wake it, and confirm the active workspace is visible while inactive workspace windows remain parked.
4. Repeat in Independent Displays mode with a different active workspace on each display.
5. For the topology case, sleep while docked and wake undocked (then reconnect), or disconnect/reconnect
   the external display immediately around sleep. The laptop/main display is the temporary fallback;
   reconnecting must restore the external workspace home and its prior active selection.
6. If anything is wrong, reproduce once and use the primary app menu's **Copy Recent Diagnostics**. The correlated
   `lifecycle` records include the wake generation, topology, bounded attempts, deferred windows, and
   final active-workspace map without window titles or document content.
