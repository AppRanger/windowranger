# WindowRanger

> **Pre-release:** WindowRanger is under active development. The first signed and notarized Beta is
> publicly available, with live-validation work still outstanding.

A small, native macOS virtual-workspace manager built around one workflow rather than a
general-purpose command language.

WindowRanger will use three release channels: Stable from `main`, Beta from release branches, and
rolling Dev builds from `develop`. Stable and opt-in Beta updates will use Sparkle later; Dev builds
will remain outside automatic updates.

Download the signed and notarized
[`v0.1.0-beta.1` GitHub prerelease](https://github.com/windowranger/windowranger/releases/tag/v0.1.0-beta.1)
as a DMG, with a notarized ZIP as a fallback. GitHub's automatically generated source archives are
not an installable macOS app.

## Project documentation

- [Canonical work queue](TODO.md)
- [Architecture](ARCHITECTURE.md)
- [Contributing](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Governance](GOVERNANCE.md)
- [Support](SUPPORT.md)
- [Release channels and branching](docs/release-channels-and-branching.md)
- [First GitHub release runbook](docs/first-github-release.md)
- [Release notes template](docs/release-notes-template.md)
- [WindowRanger 0.1.0 Beta 1 release notes](docs/releases/v0.1.0-beta.1.md)
- [Daily use and local development](docs/daily-development-workflow.md)
- [Permissions and privacy](docs/permissions-and-privacy.md)
- [Security policy](SECURITY.md)
- [Pre-release checklist](docs/release-checklist.md)
- [Portable profile transfer design](docs/profile-transfer-design.md)
- [Future workspace systems decision brief](docs/future-workspace-systems-decisions.md)
- [Two-arrow Tiled placement](docs/two-arrow-tiled-placement-recommendation.md)
- [2026-08-08 code review](docs/code-review-2026-08-08.md)
- [Third-party reference notices](THIRD_PARTY_NOTICES.md)
- [MIT license](LICENSE)

## Current feature set

- Three native, display-aware menu-bar presentations: Compact by default, Medium chips, or a Full display-grouped workspace strip.
- A standard menu from the primary app item with Settings and a graceful Quit command; the primary item never switches workspaces.
- Virtual workspaces that remember window membership and the active workspace across app restarts.
- Named reusable profiles with local manual/automatic selection, dock and exact-topology triggers, synced abstract display roles, and per-Mac monitor bindings.
- Previewed portable JSON profile export/import that adds fresh reusable definitions without transferring or changing this Mac's active profile, triggers, monitor bindings, runtime workspaces, or open windows.
- Switching parks windows from inactive workspaces at the edge of the desktop and restores their previous frames when returning.
- Workspace switches restore the destination before parking the source, touch only those two workspaces, issue position-only Accessibility writes, and suppress participating apps' own move animation for the duration of each batch.
- Global shortcuts matching the current AeroSpace configuration.
- Native sidebar-based, searchable and resizable Settings with one consolidated Workspaces master
  list and inspector for workspace identity, display mode/home, layout geometry, derived shortcuts,
  reset, and recovery. Wide panes keep their multi-column hierarchy; at compact sizes they switch to
  explicit sections and stack dense controls instead of clipping them. Its sidebar footer identifies
  the running version, build, source commit, and Dev configuration when applicable.
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

Window discovery treats a successful per-application Accessibility window enumeration as the
authoritative lifecycle snapshot for that application. A native tab/window identity absent from a
successful snapshot is removed immediately from the registry, focus history, Tiled tree, and next
persisted state, so closed or inactive tab identities cannot leave ghost layout slots. A failed or
incomplete enumeration is not evidence that a window closed and retains prior state for recovery.

Default shortcuts:

| Action | Shortcut |
| --- | --- |
| Switch to workspace | Control-Option-`workspace key` |
| Move focused window | Option-Command-`workspace key` |
| Previous / next workspace | Control-Option-`[` / `]` |
| Switch back and forth | Control-Option-Tab |
| Previous / next window | Option-`[` / `]` |
| Select or rotate Accordion / Tiled | Option-`,` / `.` |
| Toggle focused window floating | Control-Option-F |
| Focus left / down / up / right | Option-H / J / K / L |
| Reorder left / down / up / right | Control-Option-Left / Down / Up / Right |
| Place at a Tiled corner | Control-Option plus two perpendicular arrows within 200 ms |
| Smart resize smaller / larger | Control-Option-`-` / `=` |
| Move current workspace to next display | Option-Shift-Tab |
| Open contextual command wheel | Control-Option-Space (configurable) |

Shortcut validation has one shared model for global commands, the command-wheel trigger, and every
derived workspace switch/move chord. Settings names all commands in a collision and leaves the
conflicting chord unowned until it is repaired; it never silently lets the first command win. If
macOS rejects an otherwise unique global registration (for example because another app owns it),
only that command is skipped and its recorder shows the failure. Other valid shortcuts remain
registered. If the shared event handler itself cannot be installed, registration fails closed rather
than reporting shortcuts that cannot dispatch. Recording temporarily unregisters the app's bindings
and restores them as one clean generation when recording ends; a rare failed OS unregistration is
kept retryable while its old action is made inert immediately.

The four configurable Reorder bindings also form one optional two-arrow family when they use the
same modifiers, have distinct keys, and all register successfully. A first direction waits for its
release or a perpendicular partner for at most 200 ms, so it never moves and then replays a corner
placement. Up+Right, Up+Left, Down+Right, and Down+Left use the command wheel's matching Tiled
placement transaction. Accordion and Freeform report an honest no-op. If the family is incompatible
or macOS cannot observe the bounded gesture, Settings explains why and the ordinary single-arrow
commands continue to work. A successful compass placement is registered with native Undo; the app
menu exposes Undo/Redo while that exact participant set and tree remain current.

General Settings also offers an off-by-default, per-Mac trackpad gesture. Choose three or four
fingers, then swipe horizontally once to move to the adjacent workspace; cycling wraps at both ends.
The gesture dispatches through the same workspace-cycle command as the keyboard, so Independent
Displays continues to use the interaction display. WindowRanger observes without suppressing the
original trackpad event, switches at most once before every finger lifts, and pauses the monitor
during full-screen game, sleep, inactive-session, and shortcut-recording states. This optional path
depends on macOS exposing generic gesture contacts to an Accessibility-authorized event tap; if the
OS does not provide them, Settings reports that workspace swiping is inactive.

## Build

Generate the Xcode project:

```sh
xcodegen generate
```

Open `WindowRanger.xcodeproj`, select a Development Team, and run the `WindowRanger` scheme. The app requests Accessibility access on first launch. iCloud key-value sync requires a signed build with the iCloud capability available to the selected team.

Quit AeroSpace before testing the global shortcuts: macOS lets only one app register a given Carbon hotkey, and the defaults intentionally overlap your AeroSpace bindings.

For side-effect-free automated tests:

```sh
./scripts/verify-test-isolation.sh
xcodebuild -project WindowRanger.xcodeproj -scheme WindowRanger -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

`./scripts/verify-local-ci.sh --quick` packages those checks into one command. Contributors may opt
this clone into exact-commit pre-push verification with `./scripts/install-git-hooks.sh`; the hook
uses an isolated worktree and never builds or launches the app. See [Contributing](CONTRIBUTING.md)
for the full local checkpoint and hosted-CI policy.

The unit-test bundle is deliberately non-hosted: it compiles the shared sources directly and
excludes `AppDelegate`, so tests never launch WindowRanger, request Accessibility access, register
hotkeys, manage live windows, or build/register a `WindowRanger.app`. Do not give automated tests a
temporary `-derivedDataPath` and do not add the app target back to the scheme's Test build action.
Xcode's macOS app build step registers every built app with LaunchServices; current Xcode provides no
supported per-build opt-out. App builds should therefore use the normal Xcode DerivedData location,
while background verification should invoke the isolated Test action above.

The three menu-bar components also have an opt-in offscreen Retina fixture built from the production
views. It runs in the same non-hosted test bundle and does not start the app or Accessibility paths:

```sh
./scripts/render-menu-bar-previews.sh /path/to/output-directory
```

The selected three-column Workspaces Settings screen has the same isolated production-render path:

```sh
./scripts/render-settings-preview.sh /path/to/output-directory
```

The current selected-reference review and durable output paths are recorded in `design-qa.md`.

The scheme runs as **Debug** from Xcode and archives as **Release**. Both configurations currently
use the `com.windowranger.WindowRanger` bundle identifier, but Apple Development and Developer ID
signatures have different designated requirements. macOS can therefore require separate
Accessibility approval when switching between the Xcode Debug product and the installed release;
only one copy should run at a time. A distinct development-only app identity is tracked separately
and will not change the Stable/Beta identity without an explicit decision. Debug app runs write
structured JSON Lines diagnostics to
`~/Library/Logs/com.windowranger.WindowRanger/diagnostics.jsonl`; the file rotates at 1 MB and retains two
1 MB backups. Release builds do not create this verbose file. Unit tests use memory or no-op loggers
and never write there.

Option-clicking the status item in every build reveals **Copy Focused Window Diagnostic Report**.
It snapshots the externally focused window before the menu opens and copies a bounded, versioned,
read-only report covering Accessibility reads, admission, workspace/layout state, expected versus
observed geometry, and only related recent in-memory command events. It never focuses, raises,
moves, resizes, admits, or unparks the subject. Review the privacy header before sharing. Debug
builds additionally reveal **Copy Recent Diagnostics** (a bounded recent excerpt with its privacy
notice) and **Reveal Diagnostics File** for that menu opening. Opening the menu normally keeps those
support controls hidden. Diagnostics contain action/session
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
enabled. New installations start local-only until **Sync settings with iCloud** is explicitly enabled.
Turning sync off stops cloud reads and writes without deleting local settings or previously synced
cloud data. This Mac always keeps its active profile, manual pin, automatic trigger mappings,
per-profile active workspace state, conservative monitor fingerprints, and role-to-monitor bindings
locally. A missing, disconnected, or ambiguous role safely falls back without rewriting the synced
role assignment.

The atomic synced profile-library value is limited to 750,000 encoded bytes, 128 profiles, 128
workspaces and 64 display roles per profile, 512 app rules per profile, and 256 characters per
user-facing name. These deliberately leave room inside iCloud key-value storage's shared 1 MB quota.
Existing local private-install data is never deleted or truncated to meet a sync limit. If a local
or remote library exceeds a limit, the local library remains authoritative and General Settings
shows the reason; when the local copy is valid, recovery requires the explicit **Replace iCloud
Profile Library with This Mac** action.

Automatic selection resolves in a fixed order: a manual pin; an exact known display topology; a
generic docked or undocked rule on portable Macs; then this Mac's default profile. A manual selection
cannot be cleared by wake, timers, or later display events—choose **Resume Automatic** in Profiles
Settings or the app menu to release it. A portable Mac with only its built-in display is undocked; a
portable Mac with an external display is docked. Desktop Macs skip that generic distinction.

The Profiles Settings pane can create a profile from the current reusable configuration, duplicate,
rename, select, and safely delete profiles; it also manages this Mac's triggers and physical role
bindings. At compact window widths, **Profiles** and **Selection & Displays** become explicit
segments rather than two squeezed columns. Switching profiles first recovers eligible managed
windows to meaningful visible frames,
then applies the destination workspaces, display state, and app rules. Still-open windows are routed
by destination app rules or conservatively placed on an active destination workspace rather than
retaining membership from the old profile. Ignored panels and temporarily unsafe minimized or
full-screen windows remain untouched. The app menu shows the active profile and its selection reason
and provides quick switching without making the primary menu-bar item a workspace action.

On the first profile-capable launch, the existing private installation's reusable configuration is
backed up, converted into **Current Setup**, saved in the new profile format, and decoded back for
verification before the old settings keys and backup are removed. Profile-backed storage is then the
sole configuration authority.

## Workspace Settings

Workspaces is the single place for workspace-specific configuration. The normal Settings sidebar
stays on the left, a reorderable workspace master list sits in the centre, and the selected
workspace's inspector fills the right. At compact widths the master list and selected inspector
become switchable segments, and paired geometry controls stack when horizontal room runs out. The
page owns Unified versus Independent Displays, workspace
names/order/keys, abstract Home Display roles, Freeform/Tiled/Accordion choice, orientation, Tiled
gaps and screen padding, Accordion visible-edge padding, and both reusable-setting reset and live
window recovery. Profiles remains separate for reusable profile management and this Mac's physical
monitor bindings; Shortcuts remains separate for global commands.

Each workspace key produces read-only summaries of the exact derived commands: Control-Option-key
switches to it and Option-Command-key sends the focused window there. Add and Duplicate resolve a
unique name and supported key automatically. Drag reorder, context-menu and VoiceOver Move Up/Down,
safe deletion, native Undo for **Reset This Workspace**, and **Restore WindowRanger Defaults** all
use the same profile-backed storage path. Saved or deep-linked legacy Displays and Layouts panes now
open the corresponding Workspaces inspector instead of leaving a stale destination.

## Contextual command wheel

The command wheel is a global interaction preference, not part of a profile. Its shortcut uses the
same recorder, conflict detection, and reset behavior as other global commands, with
**Control-Option-Space** as the migration-safe default. **Press to Toggle** preserves the original
interaction. **Hold to Show** waits for the configured 0.15–1.0 second threshold, captures one exact
window/workspace/display context, and commits the highlighted command on release; a short tap,
Escape, stale context, or release without a valid selection cancels safely. The initial Carbon-based
recorder still requires a modifier plus a non-modifier key.

An additional **Hold Globe/Fn to show Command Wheel** option is available and defaults off. It is
local to each Mac rather than profile-owned or iCloud-synced. A quick tap and any Fn chord are
forwarded unchanged so macOS keeps the user's native Globe action; only a deliberate hold past the
shared delay opens the same nonactivating wheel, and release commits its current selection. The app
never invokes or replays the emoji picker. Compatible built-in and external keyboards share the
same public-event behavior because Quartz does not provide a dependable device identity here. The
implementation follows Apple's public event-tap/Accessibility interfaces and was compared with
[Loop at pinned revision `2467291f3095a571e80fdb0024845d4dedf111c9`](https://github.com/MrKai77/Loop/tree/2467291f3095a571e80fdb0024845d4dedf111c9).

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
references only: WindowRanger uses its own contextual command catalogue, geometry, native material
treatment, accessibility semantics, and profile boundary rather than copying their branding, assets,
or snap-centric command layouts.

The complete interaction/provider contract is documented in
[Contextual Radial Menu](docs/radial-menu-design.md). Its subordinate
[Radial Tiled Placement](docs/radial-tiled-placement.md) contract defines compass-style choices that
preview deterministic tiled-tree transformations without Accessibility writes, then commit the
validated proposal through one normal layout transaction. Tree state remains local to the current
WindowServer session and never becomes synced profile configuration.

## Current behaviour and limits

Window membership, original positions, per-window floating overrides, and the active workspace are saved locally in `~/Library/Caches/com.windowranger.WindowRanger/workspace-state.json` for the active profile. On a normal quit, the state is saved before every managed window is made visible again. On the next launch, exact window-ID and app-bundle matches are returned only when the saved profile and WindowServer session remain valid; the previously active workspace is shown, and inactive workspaces are parked again.

Recovery-state replacement is atomic and private to the user. A failed write remains retryable, an
externally removed cache file is recreated on the next persistence tick even when workspace state has
not changed, and corrupt, oversized, wrong-version, or wrong-WindowServer-session data is ignored
rather than trusted.

Window IDs are only trusted inside the same WindowServer session. After logout, reboot, or a WindowServer restart, stale assignments are ignored rather than guessed. If a crash or Xcode Stop leaves a window parked, the continuously saved state normally reconstructs it on the next launch; an unmatched parked window is instead recovered to the main display.

Sleep/wake recovery is lifecycle-driven rather than left to the background window poll. Before sleep,
the app persists workspace intent and invalidates delayed focus/layout work. Wake, screen-wake, user-
session activation, and display-topology notifications coalesce into one generation: portable monitor
homes resolve first, fresh Accessibility window lists are acquired next, and visibility/layout is
applied from the stable snapshot. A changed topology or temporarily incomplete AX enumeration gets
at most two bounded retries. The resulting Tiled and Accordion frames are then read back over a
bounded period; only split windows that remain eligible and do not match the solved frame are retried.
Minimized, full-screen, floating, ignored, disappeared, or still-unresponsive windows are left
untouched rather than being moved from stale AX elements. A changed WindowServer session keeps the
active workspace intent but discards unsafe exact window IDs.

Native macOS full-screen windows use an explicit fail-closed session. A true Accessibility full-screen
observation enters immediately; failed or unsupported reads retain an existing session, and two
consecutive authoritative false reads are required to leave it. During the session WindowRanger
performs no position or size writes for that window. For apps declaring Game Mode support or a Games
category, foreground sessions also suppress the command wheel and command-feedback panels, retain
only workspace-navigation hotkeys, reserve Command-Escape for macOS Game Overlay, and reduce broad
window discovery while still checking promptly for full-screen exit. Returning to the workspace
focuses the native full-screen window without restoring a frame or moving it between displays.

Lifecycle wiring follows Apple's documented notification centers and boundaries:
[NSWorkspace willSleep](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification),
[didWake](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification),
[sessionDidBecomeActive](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidbecomeactivenotification),
and AppKit's main-actor
[didChangeScreenParameters](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification).

Inactive windows are parked at the lower-right desktop edge because public macOS APIs do not provide a per-window hide operation. Unified mode keeps one active workspace across every display. Independent Displays mode gives each display its own active workspace and assigns each workspace an abstract display-role home. Role assignments sync with their profile, while this Mac retains the physical UUID/fingerprint binding locally; a disconnected role falls back safely and returns on reconnect. The Settings recovery button restores every tracked window; if a prior crash or force-stop left only a parked coordinate to recover, it centers that window on the main display without resizing it. A normal app quit performs the same cleanup. Animation suppression is temporary and app-scoped; it does not change macOS system animation or Accessibility settings.

Layout is selected independently for each workspace. **Freeform** preserves manual window frames and stops automatic positioning or resizing; WindowRanger still manages workspace visibility, focus, persistence, display assignment, and quit/wake recovery. Tiled uses a session-local, non-overlapping binary split tree derived migration-safely from stable order and per-window weight. Resizing a focused tile adjusts the nearest compatible divider, a position-only title-bar drag can swap it with the tile under the pointer on release, and contextual edge/corner placement previews and commits through the same tree calculation. Accordion follows the current AeroSpace-style overlapping stack with the focused window promoted to its primary pane. Both automatic layouts can resolve orientation from the display shape or use an explicit horizontal/vertical direction, with per-workspace inner gaps, outer screen padding, and configurable Accordion visible-edge padding. In Unified mode each display's windows are laid out separately according to saved display affinity; Independent Displays mode lays the workspace out only on its assigned display. The persisted raw value remains `none`, so existing and legacy saved definitions migrate without changing behavior.

Tiled and Accordion preserve AppKit's menu-bar, camera-housing, and visible-Dock safe edges. When the
user's Dock preference is auto-hide, WindowRanger deliberately restores only the configured Dock
edge to the full display boundary; this avoids retaining AppKit's transient Dock reveal strip after
leaving a full-screen game. Changing Dock hiding or its bottom/left/right orientation is picked up by
the normal display refresh and does not require relaunching WindowRanger.

Option-comma selects Accordion and Option-period selects Tiled. Selecting a different layout keeps
its saved orientation, or uses Automatic for an unconfigured workspace. Pressing the same direct
shortcut again alternates the visible layout between horizontal and vertical; an Automatic
orientation first resolves from the interaction display and then changes to the opposite concrete
direction. Tiled orientation changes retain the session tree's window identities, topology and
ratios rather than rebuilding membership or focus.

Control-Option-F toggles only the focused managed window between Floating and the workspace layout, matching the existing AeroSpace binding. Enabling Floating captures the current frame and leaves the window in its workspace while the remaining windows reflow; disabling it immediately returns the window to Tiled or Accordion. The override is restored only when the exact window ID and bundle identifier still match within the same WindowServer session, and is discarded with other stale window state. An app-level layout-exclusion rule is authoritative: the shortcut makes no contradictory override and the menu-bar icon briefly explains why.

Dialogs use the same managed workspace membership, visibility, focus, display affinity, persistence, and quit recovery as normal windows, but high-confidence dialogs float automatically so they do not distort Tiled or Accordion. High-confidence signals are an Accessibility sheet role, a system-dialog subrole, or a layer-0 dialog/floating-window subrole corroborated by reliable window-control metadata. Ambiguous dialog-like windows remain in the layout; a missing or failed Accessibility read is never treated as positive evidence. Verified nonzero-layer Codex transient panels remain ignored entirely.

Layout precedence is explicit and deterministic: an app-level **Do not include in Tiled or Accordion** rule wins first; a per-window Control-Option-F choice wins over automatic behavior; verified dialog floating applies next; an opt-in per-app **Float detected dialogs and secondary windows** rule can also float conservatively ambiguous dialog-like metadata; otherwise a normal window participates in layout. The secondary-window rule never uses titles and never infers from size or non-resizability alone. Pressing Control-Option-F on an automatically floated window forces it into the current layout, and pressing it again makes it explicitly floating. Only the explicit per-window choice persists for the exact window ID within the current WindowServer session. Automatic classification is reevaluated from live metadata and is never copied onto a newly created window ID.

Application Rules are selected from installed or currently running apps and are stored by bundle identifier rather than file path. The picker groups open apps first. When an open app's managed windows all belong to one WindowRanger workspace, a newly created rule starts with that workspace assigned; windowless apps and apps split across multiple workspaces retain the conservative **Use current workspace** default. A workspace assignment routes newly discovered windows to that workspace; in Independent Displays mode it also follows that workspace's display home. You can still move an individual window elsewhere manually, and that override survives routine window refreshes. Moving it back to the assigned workspace clears the override; changing the App Rule or profile, resetting its workspace, reopening the window, or choosing Reset All Windows reapplies the rule. Keep on all workspaces takes precedence over assignment, prevents parking, and preserves the window's existing display affinity. Layout exclusion leaves the app's windows at their current frames while the remaining windows participate in Tiled or Accordion. Secondary-window floating is narrower and preserves ordinary document-window layout participation. No rules are created during migration, so existing behavior is unchanged until a rule is added.

Rules can be paused without deleting their saved actions. Rule edits apply immediately to managed windows and participate in the Settings window's normal Command-Z Undo chain. Disabled rules remain persisted and synced, but resolve to no behavior until resumed.

Existing global command shortcuts can be recorded and reset in Settings. The recorder temporarily suspends WindowRanger's Carbon registrations, rejects bare typing and conflicts with workspace, command-wheel, or other command bindings, and preserves every established default until the user explicitly changes it. Workspace-specific switch/move bindings remain configured with the workspace definitions; no default chord was invented for selecting Freeform.

Moving a focused window is send-only by default: the source workspace remains active and focus moves to the next eligible visible window on the same interaction display. **Focus follows moved window** is opt-in in General Settings, and the command wheel always offers a one-shot **Move & Follow** action. If no local source window remains, internal focus state is cleared rather than selecting a parked or other-display fallback. General Settings can also opt this Mac into a click-through focused-window border with its own local colour, defaulting to white. Independent local filters can limit the border to Tiled workspaces, workspaces with multiple managed windows, or both. While enabled, Tiled and Accordion reserve four points at each screen edge for the border even when a filter currently hides it; Freeform frames remain user-controlled. The border uses a conservative default corner radius selected by macOS generation because public window metadata does not expose another app's rendered corner radius: macOS 27 and later use 16 points, while earlier releases retain the 10-point fallback. App Rules can override that radius for one bundle identifier on this Mac; the appearance override is local and does not sync with the rule's behavioral actions. The border also hides for WindowRanger-owned windows, apps identified as games through public bundle metadata, full-screen windows, and while the session is suspended.

Menu-bar presentation is selected in General Settings and syncs with other global settings through iCloud when enabled. **Compact** (the migration-safe default) uses an overlapping-window app symbol plus one tiny screen/workspace signal per connected logical display. **Medium** uses an equal-height chip for every display's active workspace. In both modes the interaction display receives a restrained accent, every indicator is informational, and the entire status component opens the app menu. **Full** uses lightweight display groups containing explicit workspace actions; only a primary click on a workspace switches to it. A primary click on the app or display area where present, a secondary click anywhere, or the primary VoiceOver action opens the app menu. Independent Displays shows each connected display's own active workspace simultaneously, while Unified uses one combined-displays signal and one workspace set. Each profile display role has its own Automatic, Horizontal Monitor, Vertical Monitor, Laptop, or None icon choice beside that role's local physical-display binding. The choice follows profile cloning, transfer, and optional iCloud sync; the actual monitor binding remains local to each Mac. Automatic derives the display-aware symbol from the monitor currently bound to the role. None removes only that display block's icon and gap while retaining workspace labels, controls, menu ownership, and accessibility context. Unified keeps one Automatic combined-displays symbol because its block does not represent one physical display.

Full workspace segments show an immediate restrained rollover so the pointer target is clear before clicking. After a short hover, a nonactivating Liquid Glass shelf lists the managed apps assigned directly to that workspace; selecting one switches to the workspace and focuses that app without allowing the shelf itself to take focus. Multiple managed windows from the same app appear as one row with a count, and an empty workspace is stated explicitly without an unnecessary scrollbar. Longer lists scroll only when they exceed the bounded eight-row viewport. macOS 14–25 use the system menu material where native Liquid Glass is unavailable. On macOS 27 the owning display-group button tracks those visual segment regions and resolves hover from the same public global pointer geometry used for clicks; returning from the shelf performs one bounded pointer re-check during its dismissal grace so the segment rollover is restored even when AppKit omits the enter event. The visual children remain noninteractive.

Long names remain available to tooltips and VoiceOver while visible labels are bounded. Under severe notch or menu-bar pressure, Full first compacts labels, then hides inactive buttons deterministically behind a disclosed `+N` overflow while keeping every connected display and its active workspace visible. Missing display homes are not shown as connected and are never rewritten by this presentation layer. Existing private-install values migrate once: Compact and Icon Only become Compact, Active Workspace Label becomes Medium, and Full Workspace Strip becomes Full.

The choices deliberately combine a few proven patterns rather than copying a single product: AeroSpace exposes the current workspace in its tray icon, AeroSpork renders active per-monitor workspace chips, Loop uses a compact icon-led menu, and BetterStage allows selectable status content. WindowRanger keeps an always-accessible menu target in every mode so presentation choices cannot strand Settings or Quit. Compact, Medium, and Full on macOS 14–26 use one persistent item and its custom interaction view. macOS 27 treats one custom status-item view as one interaction target, so Full instead uses one standard status item per logical display group and hides the now-redundant standalone app item. Each group moves as one menu-bar item; its standard button owns the action and resolves a primary workspace click from the public global pointer position against live screen-space segment frames. Display, overflow, unresolved, secondary, Control-, and accessibility actions open the menu. No event monitor, private system process, or app-wide gesture override is used. Every menu action presents the same standard `NSMenu` through public AppKit APIs.

High-frequency command feedback uses one centered, pill-shaped, click-through nonactivating overlay rather than a status-item popover or notification banner. On macOS 26 and later it uses AppKit's native regular Liquid Glass surface; macOS 14–25 use the system HUD material fallback. It follows the resolved interaction display, never becomes key or main, coalesces rapid updates, and cleans itself up across display changes, sleep, and quit. Debug diagnostics record the overlay lifecycle and display decision without recording its message text. In Debug Settings, **Window Admission** can also show the engine's existing privacy-safe managed/floating/deferred/ignored classifications and reasons; refreshing that view does not re-enumerate, move, resize, or focus windows.

Switching to a workspace focuses an eligible window in that workspace on the resolved destination display. In Independent Displays mode, the workspace's logical home chooses which active-workspace slot changes, while its currently connected home or safe physical fallback chooses where focus is attempted; other displays remain untouched. Local focus history is preferred, then deterministic visible local order. If macOS rejects every destination focus attempt, a stale focus report for the just-parked source window cannot reverse the explicit workspace switch; a later explicit app activation still follows that app normally. An empty workspace does not focus a parked window or steal focus from another display. Unified mode retains the actual interaction display rather than defaulting to the main display.

When the target application is inactive, WindowRanger prepares and raises the exact destination
window, then uses the public application-level Accessibility frontmost attribute. It falls back to
AppKit activation only when that Accessibility write is rejected, and retains the same bounded exact-
window verification and generation cancellation for both paths. Already-active applications use
only the exact-window path and are not reactivated. If an active application temporarily exposes no
Accessibility focused window, verification succeeds only when WindowServer independently identifies
the exact requested window as that application's frontmost on-screen normal window; a reported AX
window mismatch or competing application still fails closed. The optional focused-window border uses
the target already proven by that focus transaction during the temporary AX gap. It independently
revalidates the active application and exact WindowServer window on every poll, and retains its
fullscreen and workspace filters, so it need not wait for the delayed focused-window attribute or
perform another focus action.

Physical display-role bindings are local to each Mac. The app first matches the stable runtime display UUID, then may use a portable vendor/model/serial fingerprint when reconnecting. If multiple identical displays match, it does not guess; the workspace's synced abstract home remains intact while its physical placement falls back safely until the user chooses a binding. Option-Shift-Tab swaps the current Independent Displays workspace onto the next connected role while keeping both displays' active-workspace invariants valid.

**Open at login** uses macOS's native login-item service and changes only after an explicit Settings toggle. **Automatically unhide applications when focusing their windows** is an opt-in compatibility setting, off by default, and throttles duplicate attempts to avoid activation loops. Automated tests inject substitutes and never alter the live login-item state.

Use the primary app menu's **Quit WindowRanger** command when testing quit recovery. Xcode's Stop button terminates the debug process immediately, so macOS does not give the app an opportunity to run synchronous cleanup; continuously saved state is used to recover on the next launch instead.

## Reproducing a cross-display focus jump

1. Gracefully quit the old build with the primary app menu's **Quit WindowRanger**.
2. In Xcode, keep the `WindowRanger` scheme on its normal Debug Run configuration and click Run.
3. Focus a managed window on the second display, then use Option-`[` / Option-`]` to cycle windows.
4. With the second-display window focused, use Option-`,` or Option-`.` to change its workspace layout.
5. If focus jumps to the main display, stop after one occurrence, Option-click the status item, and choose **Copy Recent Diagnostics**. The log can instead be inspected directly with **Reveal Diagnostics File** from the same Option-revealed section.

## Retesting sleep/wake recovery

1. Gracefully quit the currently running old build with the primary app menu's **Quit WindowRanger**.
2. In Xcode, select the normal `WindowRanger` scheme and Debug Run configuration, then click Run.
3. In Unified mode, put windows from visible and inactive workspaces on both displays, sleep the Mac,
   wake it, and confirm the active workspace is visible while inactive workspace windows remain parked.
4. Repeat in Independent Displays mode with a different active workspace on each display.
5. For the topology case, sleep while docked and wake undocked (then reconnect), or disconnect/reconnect
   the external display immediately around sleep. The laptop/main display is the temporary fallback;
   reconnecting must restore the external workspace home and its prior active selection.
6. If anything is wrong, reproduce once, Option-click the status item, and use **Copy Recent Diagnostics**. The correlated
   `lifecycle` records include the wake generation, topology, bounded enumeration and frame-verification
   attempts, deferred windows, expected/observed mismatch geometry, and final active-workspace map
   without window titles or document content.
