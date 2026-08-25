# WindowRanger

> **Pre-release:** WindowRanger is under active development. Signed and notarized Beta builds are
> publicly available, with live-validation work still outstanding.

A small, native macOS virtual-workspace manager built around one workflow rather than a
general-purpose command language.

WindowRanger will use three release channels: Stable from `main`, Beta from release branches, and
rolling Dev builds from `develop`. Stable and opt-in Beta builds contain Sparkle update support;
Dev builds remain outside automatic updates. The public feed will be activated only after its first
signed update archive passes the packaged-app upgrade checks.

Download the signed and notarized
[`v0.1.0-beta.8` GitHub prerelease](https://github.com/AppRanger/windowranger/releases/tag/v0.1.0-beta.8)
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
- [Sparkle update design and release flow](docs/sparkle-updates.md)
- [WindowRanger 0.1.0 Beta 8 release notes](docs/releases/v0.1.0-beta.8.md)
- [WindowRanger 0.1.0 Beta 7 release notes](docs/releases/v0.1.0-beta.7.md)
- [WindowRanger 0.1.0 Beta 6 release notes](docs/releases/v0.1.0-beta.6.md)
- [WindowRanger 0.1.0 Beta 5 release notes](docs/releases/v0.1.0-beta.5.md)
- [WindowRanger 0.1.0 Beta 4 release notes](docs/releases/v0.1.0-beta.4.md)
- [WindowRanger 0.1.0 Beta 3 release notes](docs/releases/v0.1.0-beta.3.md)
- [WindowRanger 0.1.0 Beta 2 release notes](docs/releases/v0.1.0-beta.2.md)
- [WindowRanger 0.1.0 Beta 1 release notes](docs/releases/v0.1.0-beta.1.md)
- [Daily use and local development](docs/daily-development-workflow.md)
- [Permissions and privacy](docs/permissions-and-privacy.md)
- [Security policy](SECURITY.md)
- [Pre-release checklist](docs/release-checklist.md)
- [Portable profile transfer design](docs/profile-transfer-design.md)
- [Future workspace systems decision brief](docs/future-workspace-systems-decisions.md)
- [Omarchy-inspired product research](docs/omarchy-inspired-ideas.md)
- [DesktopRanger integration direction](docs/desktop-ranger-integration.md)
- [Two-arrow Tiled placement](docs/two-arrow-tiled-placement-recommendation.md)
- [2026-08-08 code review](docs/code-review-2026-08-08.md)
- [Third-party reference notices](THIRD_PARTY_NOTICES.md)
- [MIT license](LICENSE)

## Current feature set

- A resumable seven-stage first-run setup for iCloud, Navigate/Arrange shortcuts, Focus Border,
  menu-bar presentation, the Quick App Shelf, and keyboard/trackpad workspace navigation. Every
  choice edits the same setting used by the app; only the wizard's versioned progress remains local.
  General Settings can close Settings and restart the walkthrough from Welcome without resetting
  those choices.
- Three native, display-aware menu-bar presentations: Compact by default, Medium chips, or a Full display-grouped workspace strip.
- A standard menu from the primary app item with Settings and a graceful Quit command; the primary item never switches workspaces.
- Virtual workspaces that remember window membership and the active workspace across app restarts.
- Named reusable profiles with local manual/automatic selection, Game Mode, dock and exact-topology triggers, synced abstract display roles, and per-Mac monitor bindings.
- Previewed portable JSON profile export/import that adds fresh reusable definitions without transferring or changing this Mac's active profile, triggers, monitor bindings, runtime workspaces, or open windows.
- Switching parks windows from inactive workspaces at the edge of the desktop and restores their previous frames when returning.
- Workspace switches restore the destination before parking the source, touch only those two workspaces, issue position-only Accessibility writes, and suppress participating apps' own move animation for the duration of each batch.
- Two learnable, configurable global shortcut families: Navigate for finding workspaces and windows,
  and Arrange for moving windows and changing layouts.
- Native sidebar-based, searchable and resizable Settings gives General, Sync, Behavior, Menu Bar,
  Shortcut Guide, and Focus Border their own destinations, separate from reusable configuration
  and controls.
  Workspaces retains one consolidated master
  list and inspector for workspace identity, display mode/home, layout geometry, derived shortcuts,
  reset, and recovery. Wide panes keep their multi-column hierarchy; at compact sizes they switch to
  explicit sections and stack dense controls instead of clipping them. Its sidebar footer identifies
  the running version, build, source commit, and Dev configuration when applicable.
- Two multiple-display modes: unified switching across all displays, or independent active workspaces assigned per display.
- Workspace-local window focus cycling with `Control-Option-,` and `Control-Option-.` by default, wrapping without selecting
  parked windows. A managed standard window that has not yet been activated after restart remains
  reachable when it exposes a writable exact-focus route, while overlays and ambiguous read-only
  surfaces stay excluded.
- Spatial Navigate-arrow focus wraps from an outer workspace edge to the opposite edge without
  crossing the active workspace or display. An open Quick App Shelf uses the same wrapping rule
  along its layout axis and ignores perpendicular arrows.
- Automatic workspace following when a managed window is focused through the Dock or another macOS route.
- Per-workspace Freeform, Tiled, and Accordion layouts with migration-safe persistence, automatic or explicit orientation, gaps, outer padding, Accordion overlap, and stable ordering/weights.
- A searchable global Command Palette with compact Quick Actions, an inline Placement Halo for window positioning, and a runtime Pause command.
- An optional, Mac-local Shortcut Guide that appears while either configured shortcut family is held,
  using a passive bottom key map by default and deriving every visible action from the active
  profile's conflict-checked shortcuts. Compact headings distinguish workspace, window, layout, and
  display targets, while the arrow pad names its spatial focus or reorder behavior below the keys.
  It follows the focused window's resolved interaction
  display and adds rows only when a dense valid configuration would otherwise clip actions.
- A profile-aware Quick App Shelf with up to four ordered entries, palette selection, Previous/Next
  Window traversal while open, exact-window presentation, and conservative launch/recovery handling.
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
incomplete enumeration is not evidence that a window closed. Existing Tiled and Accordion
participants retain their stable layout slots while their geometry writes remain suppressed; an
authoritative minimized, fullscreen, ignored, floating, or layout-excluded state still leaves the
layout immediately.

Default shortcuts:

| Action | Shortcut |
| --- | --- |
| Switch to workspace | Control-Option-`workspace key` |
| Move focused window | Option-Command-`workspace key` |
| Previous / next workspace | Control-Option-`[` / `]` |
| Switch back and forth | Control-Option-Tab |
| Previous / next window | Control-Option-`,` / `.` |
| Focus left / down / up / right | Control-Option-Left / Down / Up / Right |
| Toggle Quick App | Control-Option-Backtick |
| Open Command Palette | Control-Option-Space |
| Select or rotate Accordion / Tiled | Option-Command-`,` / `.` |
| Toggle focused window floating | Option-Command-F |
| Reorder left / down / up / right | Option-Command-Left / Down / Up / Right |
| Place at a Tiled corner | Option-Command plus two perpendicular arrows within 200 ms |
| Smart resize smaller / larger | Option-Command-`-` / `=` |
| Move current workspace to next display | Option-Command-D |

Navigate and Arrange each have one configurable modifier prefix in Shortcuts Settings. Commands
store only a key suffix, and each workspace stores one suffix that produces a Navigate switch chord
and an Arrange move chord. A suffix must be unique within its family, while the same suffix can be
used deliberately across the two families. Shortcut validation has one shared model for global
commands, the Command Palette trigger, and every derived workspace switch/move chord across every
saved profile. Settings names all commands in a collision and leaves the
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
placement. Up+Right, Up+Left, Down+Right, and Down+Left use the matching Tiled compass
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

The seven production onboarding stages can likewise be rendered without starting the app:

```sh
./scripts/render-onboarding-previews.sh /path/to/output-directory
```

The current selected-reference review and durable output paths are recorded in `design-qa.md`.

The scheme runs as **Debug** from Xcode and archives as **Release**. Both configurations currently
use the `dev.appranger.WindowRanger` bundle identifier, but Apple Development and Developer ID
signatures have different designated requirements. macOS can therefore require separate
Accessibility approval when switching between the Xcode Debug product and the installed release;
only one copy should run at a time. A distinct development-only app identity is tracked separately
and will not change the Stable/Beta identity without an explicit decision. Debug app runs write
structured JSON Lines diagnostics to
`~/Library/Logs/dev.appranger.WindowRanger/diagnostics.jsonl`; the file rotates at 1 MB and retains two
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
Displays mode, abstract display roles and workspace-role homes, the complete app-rule collection
including paused rules, and an ordered shelf of up to four Quick Apps with presentation settings
owned once by the shelf. Each Quick App entry contains only its application identity and position
in that order. An application is either a Quick App or has normal App Rules within one profile, never
both. Exact
open-window IDs, workspace membership, frames, and focus remain local session state and are not
copied into a profile.

The profile Quick App Shelf presents one or more coordinated Quake-style exact-window overlays. It
can use non-overlapping Carousel cards or an overlapping Accordion, with a configured maximum of one
to four visible apps. That maximum applies only to configured apps that already expose one
unambiguous available window; WindowRanger never launches extra apps merely to fill the shelf. The
explicitly selected app retains the existing bounded launch behaviour.

The regular shortcut defaults to Navigate-Backtick and toggles the currently selected entry.
The Command Palette can show a specific entry or select the previous/next entry in the stable
configured order. Selection is remembered locally
for each profile without reordering its synced shelf. Opening the Command Palette keeps an already
presented shelf visible. While the shelf is presented, the normal Previous Window and Next Window
shortcuts temporarily cycle through shelf entries instead of the underlying workspace; moving to an
already visible neighbour promotes it without closing the shelf. Navigate plus an arrow instead
uses the visible Shelf geometry to focus the nearest entry in that direction, making the Shelf a
contained temporary workspace. Reaching either end of the Shelf's visual axis wraps to its opposite
edge; perpendicular arrows do nothing and never escape to a managed window behind it. The palette
retains keyboard focus
while entries are previewed, and closing it focuses the currently selected entry. The selected app
optionally expands the shelf from a chosen screen edge, defaulting to a roll-down from the top at
full usable width and 80 percent height. Left and right presentations use the same percentage as
screen width. Carousel divides the shelf across the other axis, while Accordion leaves a reachable
edge of each overlapping neighbour and keeps the selected window foremost. Every edge animation
collapses within the selected display, so a neighbouring monitor
never becomes an off-screen travel path. With animation disabled, WindowRanger applies the final
frame directly. Pressing the shortcut again or focusing another app uses macOS Hide for the Quick
App's application, avoiding the Dock minimize animation; showing it prepares the final or collapsed
frame before unhiding the application. Because Hide is application-wide, any other windows belonging
to that app follow the same hidden state. When the focused-window border is enabled, Quick App uses
the same four-point screen-edge clearance as managed layouts so the complete border remains visible;
toggling the border setting updates an already presented Quick App immediately. While owned,
that window stays outside normal workspace layout, reset, focus cycling, and frame persistence.
If a native tab switch replaces the app's exact Accessibility window identity, WindowRanger keeps
the Quick App session only when the same authoritative refresh finds one newly admitted replacement
from the same process and no second eligible window for that bundle. It transfers the prior local
workspace and restore state to that replacement; an ambiguous transition clears the session rather
than claiming an unrelated window. On startup, one unambiguous matching window is claimed before
ordinary workspace layout: an on-screen window moves directly to its configured Quick App frame on
its current display, while an exact WindowRanger-owned window whose application remains hidden stays
hidden. The hidden ownership marker is local to the current WindowServer session and is discarded
rather than applied to a different window identity. Legacy minimized-window markers do not grant
permission to unhide an application. Multiple matching windows remain
ordinary managed windows rather than being guessed between. If those multiple identities were
already present in WindowRanger's startup snapshot, the first direct Quick App toggle may activate
the inactive application once and briefly re-enumerate it without Accessibility writes. The direct
hotkey must still see the exact process and window identities recorded in that snapshot; any changed
candidate set, Quick App settings or profile change, pause, or sleep invalidates the opportunity.
This covers applications that retain transient login-restoration window objects until first
activated, even when that first interaction is much later. WindowRanger still proceeds only when
exactly one eligible window remains; Command Palette and shelf selection actions, later ambiguities,
and a genuine multi-window result continue to avoid repeated activation or guessing.
If the configured app has no available window, pressing the Quick App shortcut normally opens and
activates it so apps that create a window only when foregrounded receive their normal reopen request.
Palette-owned shelf previews launch without taking keyboard focus from the palette.
WindowRanger waits briefly for one eligible window, then claims and presents that window before
ordinary layout can move it. A missing installation, launch failure, timeout, or
multiple eligible windows produces clear feedback instead of guessing or retrying indefinitely.
Profiles can choose different ordered shelves and shared shelf presentation. These are managed in
the dedicated Quick App Shelf Settings section, while shortcuts remain global preferences. Existing
profiles migrate the first configured Quick App's presentation to the shared shelf setting.
For the app that owns the focused window, Command Palette can add it directly to the active
profile's normal Applications list or App Shelf. Moving between those destinations is labelled
explicitly because one profile never stores the same app in both. A companion host whose tagged
surfaces are ignored cannot enter App Shelf because Shelf visibility controls an entire application
process.
WindowRanger omits ambiguous neighbours and still reports a clear no-op rather than guessing when
the explicitly selected app has multiple eligible windows.

Profile definitions are stored as one versioned value and sync atomically through iCloud when sync is
enabled. New installations start local-only until **Sync settings with iCloud** is explicitly enabled.
Turning sync off stops cloud reads and writes without deleting local settings or previously synced
cloud data. The Sync pane lists the complete boundary: the profile library, Menu Bar presentation,
global shortcuts, Command Palette activation, focus-following moves, and automatic app unhide can
sync. This Mac always keeps its active profile and manual pin, automatic trigger mappings,
per-profile active workspace state and selected Quick App, conservative monitor fingerprints and
role-to-monitor bindings, trackpad, Shortcut Guide and Focus Border appearance, permissions,
login-item state, live-window state, and diagnostics locally. iCloud key-value storage does not expose a trustworthy
participating-device list, so WindowRanger does not pretend to list synced Macs. A missing,
disconnected, or ambiguous role safely falls back without rewriting the synced role assignment.

The atomic synced profile-library value is limited to 750,000 encoded bytes, 128 profiles, 128
workspaces and 64 display roles per profile, 512 app rules per profile, and 256 characters per
user-facing name. These deliberately leave room inside iCloud key-value storage's shared 1 MB quota.
Existing local private-install data is never deleted or truncated to meet a sync limit. If a local
or remote library exceeds a limit, the local library remains authoritative and General Settings
shows the reason; when the local copy is valid, recovery requires the explicit **Replace iCloud
Profile Library with This Mac** action.

Automatic selection resolves in a fixed order: a manual pin; this Mac's profile for a foreground
full-screen declared-game session; an exact known display topology; a generic docked or undocked
rule on portable Macs; then this Mac's default profile. A manual selection
cannot be cleared by wake, timers, or later display events—choose **Resume Automatic** in Profile
Switching Settings or the app menu to release it. A portable Mac with only its built-in display is undocked; a
portable Mac with an external display is docked. Desktop Macs skip that generic distinction.

Profiles Settings is the reusable library: it can create a profile from the current reusable
configuration, duplicate, edit its name and icon in Profile Status, safely delete, import, and
export profiles. The icon follows the reusable profile into the Settings selector, cloning, sync,
and portable transfer. Selecting, creating, or duplicating a library profile chooses it for editing
without changing the live desktop. **Use Profile** remains in Profile Status as the explicit action
that activates the edited profile and pins it on this Mac until automatic selection resumes. Profile
Switching owns this Mac's Game Mode, default, docked, undocked, and exact
display-setup rules. Displays owns the selected profile's Unified or Independent mode and abstract
display-role names alongside this Mac's physical monitor bindings. Workspaces, Applications, Quick
App Shelf, Displays, and profile-owned Menu Bar icons all follow the independent Settings edit
selection. Switching profiles first recovers eligible managed
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

Workspaces is the single place for workspace-specific configuration. A full-row profile selector in
the Settings sidebar makes the owner explicit and provides the same non-activating selection used by
Displays, Applications, and Quick App Shelf. Explicit activation remains in Profile Status rather
than appearing as another sidebar row. The normal Settings sidebar
stays on the left, a reorderable workspace master list sits in the centre, and the selected
workspace's inspector fills the right. At compact widths the master list and selected inspector
become switchable segments, and paired geometry controls stack when horizontal room runs out. The
page owns workspace names/order/keys, abstract Home Display roles, Freeform/Tiled/Accordion choice, orientation, Tiled
gaps and screen padding, Accordion visible-edge padding, and both reusable-setting reset and live
window recovery. Profiles remains separate for reusable profile management, Displays owns the
profile's display mode and this Mac's physical monitor bindings, and Shortcuts remains separate for
global commands.

Each workspace key produces read-only summaries of the exact derived commands: Navigate-key
switches to it and Arrange-key sends the focused window there. Add and Duplicate resolve a
unique name and supported key automatically. Drag reorder, context-menu and VoiceOver Move Up/Down,
safe deletion, native Undo for **Reset This Workspace**, and **Restore WindowRanger Defaults** all
use the same profile-backed storage path. Displays is a current destination; saved or deep-linked
legacy Layouts selections open Workspaces instead of leaving a stale destination.

## Command Palette and Window Placement

The Command Palette is a global interaction preference, not part of a profile. Its shortcut uses
the shared key-suffix map and conflict model, using **Navigate-Space** by default. It opens a
keyboard-focused search field containing the
commands currently valid for the focused window, workspace, layout, profile, and interaction
display. A compact **Quick Actions** block directly below search keeps workspace-wide layout and
focused-window placement visually separate from the command results. Its first row shows the
current workspace's **Freeform**, **Tiled**, or **Accordion** layout and changes it without closing
the palette. Its second row opens focused-window placement only when truthful placements exist.
Results also show their configured shortcuts where one exists. Arrow keys move selection, Return
runs it, and Escape or a second shortcut press closes the palette.

**Pause WindowRanger** is a transient runtime state available from the palette and app menu. While
paused, only the Command Palette shortcut remains registered; the palette offers only **Resume
WindowRanger**. Workspace swipes, shortcut guidance, focus highlighting, automatic visibility and
layout writes, and menu-bar workspace actions remain inactive. WindowRanger takes a read-only window
snapshot on resume so Tiled and Accordion changes made while paused are not learned, then reconciles
the current profile and layout once. Freeform windows remain user-positioned. Pause is never saved or
synced and always starts off after relaunch.

Opening a key window must not retarget a window-management command to WindowRanger itself. The
palette therefore captures the external interaction context and frontmost application first. It
restores that application before dispatch, then revalidates the exact window, workspace, display,
layout, profile, and generated placement token. A changed or unavailable target cancels safely.

The **Place focused window** Quick Action expands a compact **Placement Halo** from its row without
closing the palette. It contains only Loop-style positions that can be previewed truthfully for the
focused window: Freeform halves and quarters or Tiled compass placement. Layout selection,
Accordion resizing, and every other former wheel command remain searchable palette actions, while
the current workspace layout is always visible above them. When no position is available, the
entire placement row is omitted instead of showing a disabled or invented choice.

Tab enters Quick Actions without moving focus away from search. Up from the first command result
enters the visually adjacent bottom Quick Action, then Up and Down move through its stacked rows.
Left and Right change layout only while the workspace-layout row is selected. Return on the
placement row opens the Halo, whose arrow keys move around the available positions. Return commits
the highlighted placement, and Escape collapses the Halo or returns from Quick Actions to command
results. Typing hides Quick Actions and any open Halo so filtering becomes the only active mode;
clearing the query shows them again. Pointer use remains available at the same time. The
expanded transparent panel disables its AppKit window shadow so macOS does not draw an outline
around the halo; the halo retains its own bounded material shadow.

Legacy saved wheel ordering and press/hold preferences remain decodable so existing settings are
not damaged, but the current UI and runtime no longer expose the broad wheel catalogue. The obsolete
Globe/Fn preference and input-monitor implementation have been removed. Command Palette Settings now contains its enablement and a read-only resolved
shortcut summary; the shared action assignment is edited in Shortcuts.
window placement is offered contextually inside the palette itself.

The spatial interaction/provider contract remains documented in
[Contextual Radial Menu](docs/radial-menu-design.md). Its subordinate
[Radial Tiled Placement](docs/radial-tiled-placement.md) contract defines compass-style choices that
preview deterministic tiled-tree transformations without Accessibility writes, then commit the
validated proposal through one normal layout transaction. Tree state remains local to the current
WindowServer session and never becomes synced profile configuration.

## Current behaviour and limits

Window membership, original positions, per-window floating overrides, and the active workspace are saved locally in `~/Library/Caches/dev.appranger.WindowRanger/workspace-state.json` for the active profile. On a normal quit, the state is saved before every managed window is made visible again. On the next launch, exact window-ID and app-bundle matches are returned only when the saved profile and WindowServer session remain valid; the previously active workspace is shown, and inactive workspaces are parked again.

The AppRanger identity migration copies missing preferences and the current-session recovery cache
from `com.windowranger.WindowRanger` once, without deleting or overwriting either identity's data.
The iCloud key-value entitlement deliberately continues using the existing WindowRanger store so
opt-in synced settings remain available. Because macOS treats the new signed identifier as a new
application identity, users upgrading from an older Beta must grant Accessibility access again and
reconfirm Launch at Login if they use it.

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
category, foreground sessions also suppress the Command Palette and command-feedback panels, retain
only workspace-navigation hotkeys, reserve Command-Escape for macOS Game Overlay, and reduce broad
window discovery while still checking promptly for full-screen exit. Returning to the workspace
focuses the native full-screen window without restoring a frame or moving it between displays.
The optional local Game Mode profile mapping requires a foreground full-screen game whose bundle
explicitly declares `LSSupportsGameMode`. Public macOS APIs do not expose the user's live per-game Game Mode override, so WindowRanger
does not claim to observe that private system state directly.

Lifecycle wiring follows Apple's documented notification centers and boundaries:
[NSWorkspace willSleep](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification),
[didWake](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification),
[sessionDidBecomeActive](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidbecomeactivenotification),
and AppKit's main-actor
[didChangeScreenParameters](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification).

Inactive windows are parked at the lower-right desktop edge because public macOS APIs do not provide a per-window hide operation. Unified mode keeps one active workspace across every display. Independent Displays mode gives each display its own active workspace and assigns each workspace an abstract display-role home. Role assignments sync with their profile, while this Mac retains the physical UUID/fingerprint binding locally; a disconnected role falls back safely and returns on reconnect. The Settings recovery button restores every tracked window; if a prior crash or force-stop left only a parked coordinate to recover, it centers that window on the main display without resizing it. A normal app quit performs the same cleanup. Animation suppression is temporary and app-scoped; it does not change macOS system animation or Accessibility settings.

Layout is selected independently for each workspace. **Freeform** preserves manual window frames and stops automatic positioning or resizing; its contextual Place wheel can explicitly snap only the focused window to a usable-screen half or quarter, with an exact preview and Undo. WindowRanger still manages workspace visibility, focus, persistence, display assignment, and quit/wake recovery. Tiled uses a session-local, non-overlapping binary split tree derived migration-safely from stable order and per-window weight. Resizing a focused tile adjusts the nearest compatible divider, a position-only title-bar drag can swap it with the tile under the pointer on release, and contextual edge/corner placement previews and commits through the same tree calculation. Accordion follows the current AeroSpace-style overlapping stack with the focused window promoted to its primary pane. Both automatic layouts can resolve orientation from the display shape or use an explicit horizontal/vertical direction, with per-workspace inner gaps, outer screen padding, and configurable Accordion visible-edge padding. In Unified mode each display's windows are laid out separately according to saved display affinity; Independent Displays mode lays the workspace out only on its assigned display. The persisted raw value remains `none`, so existing and legacy saved definitions migrate without changing behavior.

Tiled and Accordion preserve AppKit's menu-bar, camera-housing, and visible-Dock safe edges. When the
user's Dock preference is auto-hide, WindowRanger deliberately restores only the configured Dock
edge to the full display boundary; this avoids retaining AppKit's transient Dock reveal strip after
leaving a full-screen game. Changing Dock hiding or its bottom/left/right orientation is picked up by
the normal display refresh and does not require relaunching WindowRanger.

Arrange-comma selects Accordion and Arrange-period selects Tiled. Selecting a different layout keeps
its saved orientation, or uses Automatic for an unconfigured workspace. Pressing the same direct
shortcut again alternates the visible layout between horizontal and vertical; an Automatic
orientation first resolves from the interaction display and then changes to the opposite concrete
direction. Tiled orientation changes retain the session tree's window identities, topology and
ratios rather than rebuilding membership or focus.

Arrange-F toggles only the focused managed window between Floating and the workspace layout. Enabling Floating captures the current frame and leaves the window in its workspace while the remaining windows reflow; disabling it immediately returns the window to Tiled or Accordion. The override is restored only when the exact window ID and bundle identifier still match within the same WindowServer session, and is discarded with other stale window state. An app-level layout-exclusion rule is authoritative: the shortcut makes no contradictory override and the menu-bar icon briefly explains why. A window authoritatively proven movable but not resizable also cannot be forced into layout; Arrange-F explains that it must remain floating. A structurally proven standard-window dialog likewise stays floating at its application-chosen size.

Dialogs use the same managed workspace membership, visibility, focus, display affinity, persistence, and quit recovery as normal windows, but high-confidence dialogs float automatically so they do not distort Tiled or Accordion. High-confidence signals are an Accessibility sheet role, a system-dialog subrole, a layer-0 dialog/floating-window subrole corroborated by reliable window-control metadata, a standard window with absent Full Screen/Close controls and either affirmative window-level Default and Cancel relationships or AppKit's native `open-panel`/`save-panel` Accessibility identifier, or a layer-0 standard window that has a Close control, can move, and authoritatively cannot resize. The native-panel identifier is reduced immediately to a privacy-safe true/false observation; no arbitrary identifier is retained or logged. These cases cover native Open/Save panels without inspecting localized titles, button labels, dimensions, file paths, or application identity. They and proven fixed-size windows use position-only writes, cannot consume a layout slot, and cannot be forced into one, preserving native dialog size. Each candidate gets one support probe, so an unsupported or failed relationship/identifier/capability read stays conservative without adding repeated Accessibility traffic. If a later initial size write is nevertheless rejected, WindowRanger rechecks that exact standard window once, converts it to the fixed-size safety path, and immediately completes the move without resizing. A known nonzero-layer Accessibility dialog is left untouched until its live layer metadata settles, preventing transient prompts from entering a split; an unknown layer remains conservatively managed. A rejected size write also stops before position so a fixed-size surface cannot be displaced toward a layout frame it cannot occupy. Other ambiguous dialog-like windows remain in the layout, and a missing or failed Accessibility read is never treated as positive evidence. Verified nonzero-layer Codex transient panels remain ignored entirely.

Layout precedence is explicit and deterministic: an app-level **Do not include in Tiled or Accordion** rule wins first; proven fixed-size and standard-window-dialog safety win next; a per-window Arrange-F choice wins over other automatic behavior; verified dialog floating follows; an opt-in per-app **Float detected dialogs and secondary windows** rule can also float conservatively ambiguous dialog-like metadata; otherwise a normal window participates in layout. The secondary-window rule never uses titles and never infers secondary ownership from size or non-resizability alone; authoritative structural or move/resize evidence instead decides whether a standard window can safely participate in layout at all. Pressing Arrange-F on another automatically floated dialog forces it into the current layout, and pressing it again makes it explicitly floating. Only the explicit per-window choice persists for the exact window ID within the current WindowServer session. Automatic classification is reevaluated from live metadata and is never copied onto a newly created window ID.

Externally hidden applications remain tracked so their workspace and restore state survive Hide,
but their ordinary windows reserve no layout space, receive no focus target, and receive no geometry
writes while the application is hidden. Hiding an app immediately reflows the remaining visible
windows; unhiding it returns its retained windows through the normal current/inactive-workspace
visibility path. This is separate from WindowRanger-owned Quick App hiding and does not treat Hide
as termination or a failed Accessibility snapshot.

Application Rules are selected from installed or currently running apps and are stored by bundle identifier rather than file path. The picker groups open apps first. When an open app's managed windows all belong to one WindowRanger workspace, a newly created rule starts with that workspace assigned; windowless apps and apps split across multiple workspaces retain the conservative **Use current workspace** default. A workspace assignment routes newly discovered windows to that workspace; in Independent Displays mode it also follows that workspace's display home. You can still move an individual window elsewhere manually, and that override survives routine window refreshes. Moving it back to the assigned workspace clears the override; changing the App Rule or profile, resetting its workspace, reopening the window, or choosing Reset All Windows reapplies the rule. Keep on all workspaces takes precedence over assignment, prevents parking, and preserves the window's existing display affinity. Layout exclusion leaves the app's windows at their current frames while the remaining windows participate in Tiled or Accordion. Secondary-window floating is narrower and preserves ordinary document-window layout participation. No rules are created during migration, so existing behavior is unchanged until a rule is added.

Rules can be paused without deleting their saved actions. Rule edits apply immediately to managed windows and participate in the Settings window's normal Command-Z Undo chain. Disabled rules remain persisted and synced, but resolve to no behavior until resumed.

Every explicit Settings command reassigns the existing Settings utility to the current WindowRanger
workspace and interaction display, then brings it to the front. If that window was already visible
on another native macOS Space, WindowRanger resets that old Space attachment before showing the same
window on the current Space. WindowRanger lets the originating status-item click finish before
presenting its detached menu, then a Settings selection waits until that popup has fully returned
before activating the utility. This releases menu-bar input ownership before Settings becomes key
and frontmost, so global shortcuts remain available. Closing and reopening Settings reuses and
raises SwiftUI's retained window immediately; if macOS has released it, WindowRanger requests a new
Settings scene. Returning to a workspace in the background still restores Settings without stealing
focus.

Shortcuts Settings owns the global Navigate and Arrange modifier prefixes and the key-only action map. Recording a key suffix temporarily suspends WindowRanger's Carbon registrations and rejects conflicts with workspace or other command bindings; actions can also be reset or left unassigned for palette-only use. Workspaces owns each profile workspace's one suffix and shows both derived family chords; no default chord is invented for selecting Freeform.

Moving a focused window is send-only by default: the source workspace remains active and focus moves to the next eligible visible window on the same interaction display. **Focus follows moved window** is opt-in in Behavior, and the Command Palette always offers a one-shot **Move & Follow** action. If no local source window remains, internal focus state is cleared rather than selecting a parked or other-display fallback. Focus Border can also opt this Mac into a click-through focused-window border with its own local colour, defaulting to white. Independent local filters can limit the border to Tiled workspaces, workspaces with multiple managed windows, or both. While enabled, Tiled and Accordion reserve four points at each screen edge for the border even when a filter currently hides it; Freeform frames remain user-controlled. The border uses a conservative default corner radius selected by macOS generation because public window metadata does not expose another app's rendered corner radius: macOS 27 and later use 16 points, while earlier releases retain the 10-point fallback. Focus Border owns optional application-specific radius overrides on this Mac. They are independent of profile-owned Application Rules and Quick Apps, so removing or converting either does not erase the local appearance correction. The border also hides for WindowRanger-owned windows, apps identified as games through public bundle metadata, full-screen windows, and while the session is suspended.

Menu-bar presentation is selected in Menu Bar Settings and syncs with other global settings through iCloud when enabled. **Compact** (the migration-safe default) adapts to the workspace-label choice for each connected logical display: a shortcut key sits in a symbol-specific safe area inside the horizontal-monitor, vertical-monitor, laptop, or combined-display symbol, while a compacted name appears as bare text beside a smaller symbol. It adds no status dot or enclosing badge. Name labels retain up to five characters rather than collapsing to the shortest pressure abbreviation. If that display role's icon is set to None, Compact keeps the workspace key or name as bare text. **Medium** uses an equal-height chip for every display's full active-workspace label. In both modes the interaction display receives a restrained accent, every indicator is informational, and every item opens the app menu. **Full** uses lightweight display groups containing explicit workspace actions; only a primary click on a workspace switches to it. A primary click on the app or display area where present, a secondary click anywhere, or the primary VoiceOver action opens the app menu. Independent Displays shows each connected display's own active workspace simultaneously, while Unified uses one combined-displays signal and one workspace set. Each profile display role has its own Automatic, Horizontal Monitor, Vertical Monitor, Laptop, or None icon choice in Menu Bar Settings. The choice follows profile cloning, transfer, and optional iCloud sync; the actual monitor binding remains local to each Mac and is edited in Displays. Automatic derives the display-aware symbol from the monitor currently bound to the role. None removes only that display block's icon and gap while retaining workspace labels, controls, menu ownership, and accessibility context. Unified keeps one Automatic combined-displays symbol because its block does not represent one physical display. Menu Bar Settings renders these same production display groups in its macOS 27 preview; earlier macOS releases preview their single-item compatibility presentation.

Full workspace segments show an immediate restrained rollover so the pointer target is clear before clicking. After a short hover, a nonactivating Liquid Glass shelf lists the managed apps assigned directly to that workspace; selecting one switches to the workspace and focuses that app without allowing the shelf itself to take focus. Multiple managed windows from the same app appear as one row with a count, and an empty workspace is stated explicitly without an unnecessary scrollbar. Longer lists scroll only when they exceed the bounded eight-row viewport. macOS 14–25 use the system menu material where native Liquid Glass is unavailable. On macOS 27 the owning display-group button tracks those visual segment regions and resolves hover from the same public global pointer geometry used for clicks; returning from the shelf performs one bounded pointer re-check during its dismissal grace so the segment rollover is restored even when AppKit omits the enter event. The visual children remain noninteractive.

Long names remain available to tooltips and VoiceOver while visible labels are bounded. Under severe notch or menu-bar pressure, Full first compacts labels, then hides inactive buttons deterministically behind a disclosed `+N` overflow while keeping every connected display and its active workspace visible. Missing display homes are not shown as connected and are never rewritten by this presentation layer. Existing private-install values migrate once: Compact and Icon Only become Compact, Active Workspace Label becomes Medium, and Full Workspace Strip becomes Full.

The choices deliberately combine a few proven patterns rather than copying a single product: AeroSpace exposes the current workspace in its tray icon, AeroSpork renders active per-monitor workspace chips, Loop uses a compact icon-led menu, and BetterStage allows selectable status content. WindowRanger keeps an always-accessible menu target in every mode so presentation choices cannot strand Settings or Quit. Compact, Medium, and Full on macOS 14–26 use one persistent item and its custom interaction view. macOS 27 instead uses one standard status item per logical display group in every mode and hides the now-redundant standalone app item. Each group moves as one menu-bar item and retains the system button's native press feedback. Compact and Medium group actions always open the menu. In Full, the standard button owns the action and resolves a primary workspace click from the public global pointer position against live screen-space segment frames; display, overflow, unresolved, secondary, Control-, and accessibility actions open the menu. No event monitor, private system process, or app-wide gesture override is used. Every menu action presents the same standard `NSMenu` through public AppKit APIs.

High-frequency command feedback uses one centered, pill-shaped, click-through nonactivating overlay rather than a status-item popover or notification banner. On macOS 26 and later it uses AppKit's native regular Liquid Glass surface; macOS 14–25 use the system HUD material fallback. It follows the resolved interaction display, never becomes key or main, coalesces rapid updates, and cleans itself up across display changes, sleep, and quit. Debug diagnostics record the overlay lifecycle and display decision without recording its message text. In Debug Settings, **Window Admission** can also show the engine's existing privacy-safe managed/floating/deferred/ignored classifications, reasons, matched built-in compatibility profile, modal/focus observations, window-control presence, and move/resize capability evidence. Built-in compatibility profiles correct verified unusual surfaces in popular apps automatically; personal workspace and layout preferences remain user App Rules. The deterministic copied snapshot is suitable for regression-fixture capture. Refresh performs support-only Accessibility reads for already tracked windows without re-enumerating, moving, resizing, or focusing them; Copy uses that cached result. Neither includes titles, documents, URLs, paths, typed content, or window contents.

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

Physical display-role bindings are local to each Mac. The app first matches the stable runtime display UUID, then may use a portable vendor/model/serial fingerprint when reconnecting. If multiple identical displays match, it does not guess; the workspace's synced abstract home remains intact while its physical placement falls back safely until the user chooses a binding. Arrange-D swaps the current Independent Displays workspace onto the next connected role while keeping both displays' active-workspace invariants valid.

**Open at login** uses macOS's native login-item service and changes only after an explicit Settings toggle. **Automatically unhide applications when focusing their windows** is an opt-in compatibility setting, off by default, and throttles duplicate attempts to avoid activation loops. Automated tests inject substitutes and never alter the live login-item state.

Use the primary app menu's **Quit WindowRanger** command when testing quit recovery. Xcode's Stop button terminates the debug process immediately, so macOS does not give the app an opportunity to run synchronous cleanup; continuously saved state is used to recover on the next launch instead.

## Reproducing a cross-display focus jump

1. Gracefully quit the old build with the primary app menu's **Quit WindowRanger**.
2. In Xcode, keep the `WindowRanger` scheme on its normal Debug Run configuration and click Run.
3. Focus a managed window on the second display, then use Navigate-`,` / Navigate-`.` to cycle windows.
4. With the second-display window focused, use Arrange-`,` or Arrange-`.` to change its workspace layout.
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
