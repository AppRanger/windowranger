# WindowRanger architecture

> **Pre-release:** WindowRanger remains under active private development. This document describes
> the current build; it is not a compatibility or public API contract.

WindowRanger is a native macOS menu-bar application that implements virtual workspaces without
creating or controlling native macOS Spaces. It discovers eligible windows through Accessibility,
keeps workspace membership in its own model, and makes inactive-workspace windows non-visible by
parking them at a recoverable screen edge.

## Module map

| Area | Main sources | Responsibility |
|---|---|---|
| Application lifecycle | `Sources/App` | Creates the shared stores/controllers, wires publishers, handles sleep/wake and graceful quit. |
| Commands and hotkeys | `Sources/Commands`, `Sources/Hotkeys` | Shared typed command dispatch, conflict validation, Carbon registration and event routing. |
| Window engine | `Sources/Windows` | AX discovery, admission, membership, parking/restoration, focus, layout application and wake reconciliation. |
| Reusable models | `Sources/Model` | Workspaces, layouts, profiles, display identity, app rules, window manipulation and radial-menu preferences. |
| Settings | `Sources/Settings` | Profile/iCloud-backed configuration, machine-local state, searchable native UI and app-owned Settings-window routing. |
| Onboarding | `Sources/Onboarding`, `Sources/App/OnboardingWindowController.swift` | Versioned local progress, seven settings-backed stages and first-run window presentation. |
| Command surfaces | `Sources/CommandPalette`, `Sources/MenuBar`, `Sources/RadialMenu` | Searchable and contextual presentation through the same typed command layer used by hotkeys. |
| Shortcut guide | `Sources/ShortcutGuide` | Passive modifier observation, conflict-checked key-map content, screen geometry and a nonactivating glass HUD. |
| Updates | `Sources/Updates` | Local Stable/Beta preference, Sparkle lifecycle, signed-update configuration and the hard Dev-build network boundary. |
| Diagnostics | `Sources/Diagnostics` | Structured privacy-filtered Debug traces with bounded rotation and no-op/test sinks. |

The non-hosted `WindowRangerTests` target compiles shared sources directly and excludes
`Sources/App`. It therefore tests the model and injected boundaries without starting AppDelegate,
installing production hotkeys, asking for Accessibility permission or moving live windows.

## Runtime data flow

1. `AppDelegate` creates `SettingsStore`, `WorkspaceEngine`, the shared command dispatcher,
   presentation controllers and `HotKeyManager`.
2. `SettingsStore` loads one versioned synced `ProfileLibrary` plus machine-local
   `ProfileLocalState`, then resolves abstract display roles against connected local displays.
   After the runtime publishers are wired, the onboarding controller presents when its local
   completion version is stale and binds every choice back to this same store. General Settings can
   explicitly restart only that local progress; the Settings window closes before onboarding is
   presented on the next main-loop turn, and existing configuration remains intact.
3. `WorkspaceEngine.start()` checks Accessibility trust, enumerates applications/windows and sends
   each candidate through the central admission classifier before it can enter any other subsystem.
4. Hotkeys, the optional local workspace-swipe monitor, the menu bar, and the Command Palette emit
   `WindowManagerCommand` values through one dispatcher. The engine validates current context again
   before applying a mutation.
5. Engine state changes update the menu bar, Settings utility visibility and the persisted local
   workspace session. Configuration changes flow in the opposite direction from `SettingsStore`
   into the engine through debounced publishers.
6. Debug diagnostics attach correlation IDs to a command and its resulting AX/layout/focus work.

## Virtual-workspace model

A workspace is an ordered reusable definition with a stable UUID, human name, one-character key,
layout and layout geometry. In Unified mode one active workspace applies across connected displays;
windows retain their physical display affinity. In Independent Displays mode each logical display
has its own active workspace and workspaces have synced abstract display-role homes.

Window membership is session state, not profile content. Inactive members are parked using
position-only AX writes where possible. Their recoverable frames are retained so switching back,
graceful quit, startup recovery and explicit reset can return them to meaningful visible geometry.
Exact window identities are trusted only inside the same WindowServer session.

The broad refresh captures each readable Accessibility frame once during enumeration and reuses
that observation when deciding whether background visibility or layout work is necessary. A missing
enumeration frame receives a direct retry. If the engine attempts visibility or geometry work, it
then rebuilds the signature from fresh frames so rejected, delayed, or adjusted writes cannot become
an assumed baseline; a no-write refresh retains the enumerated signature without rereading every
visible managed window.

Layout membership and Accessibility write eligibility are separate during a transient observation
gap. A failed application-window enumeration or unreadable frame for an existing Tiled or Accordion
participant preserves its last stable slot, so readable siblings are not reflowed around the gap;
the unreadable window itself receives no geometry write. A successful enumeration absence, or an
authoritative minimized, fullscreen, ignored, floating, or layout-excluded state, releases the slot
immediately.

## Window admission and precedence

`AccessibilityWindow.admissionDecision` is the sole discovery boundary. It produces one of five
dispositions: normal managed window, managed dialog (automatically floating), temporarily
ineligible, ignored persistent companion surface, or ignored transient/popup. Ignored objects never
enter membership, layout, persistence, focus cycling or recovery. The explicit companion
disposition keeps cooperative long-lived surfaces distinct from transient UI; verified
non-normal-layer Codex pet/panels remain excluded as transient objects rather than patched out later.

Built-in compatibility profiles are versioned, declarative corrections for verified application
surfaces. A profile matches a normalized bundle identifier plus only the role, subrole, layer,
modal, control-presence, move/resize evidence, or exact host-owned Accessibility identifier needed
to distinguish that surface. It produces an ordinary admission disposition and records the matched
profile identifier in diagnostics. Profiles must be backed by a privacy-safe fixture and must not
encode a user's workspace assignment or layout preference. The bundled registry is intentionally
local to the signed app; there is no remotely updated exception list.

The DesktopRanger companion contract is deliberately surface-specific and currently scoped only to
the proven SurfaceLab identity. WindowRanger reads the AX identifier only for exact bundle ID
`dev.appranger.DesktopRanger.SurfaceLab` and ignores only its exact
`dev.appranger.desktopranger.surface.v1` marker. Untagged SurfaceLab manager windows remain eligible
for ordinary admission. A future production bundle must be added only after its identity is defined
and independently evidenced. The raw identifier is classifier input, not diagnostic output; logs
and support snapshots expose only the privacy-safe reason and bundled profile identifier. If a
previously confirmed marker is temporarily unreadable, WindowRanger keeps the surface ignored; a
first unavailable read is temporarily ineligible until classification can be completed, while a
confirmed absent identifier remains an ordinary manageable window. An ignored
surface that was already tracked is removed from membership, pending restoration, layout, focus,
full-screen, and transient interaction state through the existing no-frame-write eviction path. If
it had entered Quick App state, WindowRanger discards that session and restores application
visibility through a bounded confirmation path without writing the companion surface's frame. An
unconfirmed unhide leaves a visibility-only recovery record with no window key or geometry; later
polls retry it, while a newly acquired Quick App session supersedes the old recovery generation.
The exact PID-and-bundle debt is persisted without window or frame data, retried at startup, and
receives one final unhide request during an orderly WindowRanger shutdown.

Generic admission performs one-time support reads, including move/resize capability, for an ordinary
layer-0 standard window with a Close control. When position is authoritatively writable but size is
authoritatively read-only, the window remains managed but is automatically floating. Visibility
restoration can therefore return it with a position-only write while Tiled and Accordion solve only
for windows that can actually accept their assigned frames. Missing, failed, or contradictory
capability evidence remains managed conservatively and does not trigger this fallback. A completed
negative probe is retained so the ordinary engine refresh does not repeat failed support reads.
Proven fixed-size windows use position-only writes for visibility, display reconciliation, Quick App
transitions, and quit recovery; neither an explicit per-window override nor another frame path can
force a resize-first operation. If the one-time probe was inconclusive but an initial size write
later rejects, the engine re-probes that exact candidate once, records the fixed-size decision, and
immediately completes the requested position-only move and re-solves the affected visible layouts.
Position or final-size failures do not promote a normal window into this safety classification.
An otherwise closeless standard window on an unknown or normal layer receives a separate one-time
dialog-control probe only when both its Full Screen and Close controls are authoritatively absent.
Affirmative window-level Default and Cancel button relationships classify that surface as a managed
dialog. AppKit file panels can declare those attributes while returning no relationship values, so
the same one-time probe also reduces the window's Accessibility identifier to a privacy-safe boolean
for the exact nonlocalized `open-panel` and `save-panel` identifiers. The raw identifier is neither
retained nor logged, and the identifier cannot override a window that has ordinary Full Screen or
Close controls. This covers native Open/Save panels without using localized titles, button labels,
dimensions, bundle identifiers, child content, document URLs, or paths. Missing, failed, unrelated,
or contradictory evidence remains conservatively normal. Proven standard-window dialogs are
position-only and cannot be forced into a resize layout, preserving the application's chosen size.

Effective layout participation follows this order:

1. a narrowly matched built-in compatibility profile can correct the surface's admission;
2. generic admission classifies every unmatched window;
3. ignored/transient or temporarily unsafe windows are untouched;
4. a user App Rule that excludes layout remains authoritative for admitted windows;
5. proven fixed-size or standard-window dialog surfaces remain position-only and outside layout;
6. explicit per-window floating state controls otherwise eligible windows;
7. other high-confidence dialog classification automatically floats a dialog;
8. remaining windows participate in the workspace's Freeform, Tiled or Accordion behavior.

Keep-on-all-workspaces rules affect visibility but do not grant a window permission to enter layout
or focus scopes that it otherwise fails.
An externally hidden regular application remains enumerated and tracked so its exact workspace,
restore frame, lifecycle, and WindowServer identity are not confused with termination or an AX
failure. Its ordinary windows are nevertheless excluded from active layout participants, focus
candidates/history, and every geometry-write path until AppKit reports the application visible
again. Hidden state participates in the background-layout signature so visible peers reflow on Hide
and the retained windows rejoin normal visibility/layout handling on Unhide. Exact Quick App
application-hide ownership remains governed by its separate session path.

Debug admission evidence is deliberately richer than the active classifier. The cached snapshot
distinguishes authoritative, unsupported, and unavailable modal, focused, main-window, window-control,
Default/Cancel relationship, native-file-panel-identifier, position-settable, and size-settable observations so representative real-app fixtures can justify a
later rule change. The regular engine poll retains cached support evidence rather than performing
these extra queries every 0.75 seconds. The exceptions are a surface whose bundle and ordinary
role/subrole/layer/control evidence already match a compatibility profile that explicitly requires
support-only evidence, a layer-0 standard window with a Close control that has not completed its
one-time move/resize capability probe, and a closeless normal/unknown-layer standard window that has
not completed its one-time dialog-control probe. Only those candidates are enriched
before classification. A movable standard candidate that authoritatively cannot resize floats as a
managed dialog; unavailable or unsupported evidence leaves it conservatively managed as normal and
is not retried by the poll.
An explicit `AXDialog` observed on a known nonzero WindowServer layer is temporarily ineligible for
admission instead of being placed while its transient layer metadata settles. If the same window
later reports layer zero with corroborating controls, it enters as an automatically floating dialog;
an unavailable layer remains conservatively managed. Frame writes also stop before changing
position when the initial size write is rejected, so a fixed-size surface cannot be displaced toward
a layout frame it cannot occupy.
User-triggered Refresh
performs read-only capability queries for already tracked windows, while ignored or unsupported
surfaces capture the same evidence once before they are discarded. The snapshot contains no window
titles or content-bearing metadata and does not itself change admission, membership, layout, focus,
persistence, or recovery behaviour.

The Add Application Rule picker reads existing engine membership without refreshing or mutating
windows. Open apps are presented separately from other installed apps. A new rule inherits a live
workspace only when every currently managed window for that bundle agrees on one workspace;
windowless or split-workspace apps retain no assignment so Settings never guesses a bundle-wide
rule from ambiguous per-window state.

## Persistence boundaries

### Synced reusable definitions

The profile library can sync through iCloud key-value storage. A profile contains its user-selected
Settings icon, workspace definitions/order/keys/layout geometry, Unified or Independent display mode,
abstract display roles and their menu-bar icon styles, workspace-role assignments, typed app rules, and an ordered Quick
App Shelf of up to four bundle identifier/display name entries plus one shared shelf presentation.
Legacy per-entry presentation migrates deterministically from the first configured entry. Normalization
removes duplicates, preserves configured order, and makes Quick App ownership mutually exclusive
with an App Rule for the same bundle identifier. Global preferences
such as menu-bar presentation, the Navigate/Arrange modifier families and key-suffix action map,
and Command Palette configuration use their
existing global settings path and are not profile content, but are included in the supported iCloud
sync payload when syncing is enabled. Focus-following moves and automatic application-unhide use the
same global sync path.

Workspace suffixes are durable profile content and reserve their key in both shortcut families.
When private-install migration, profile import, or iCloud data introduces a collision, the workspace
key wins and the conflicting global action becomes unassigned but remains available in the Command
Palette. Interactive editors prevent the collision before persistence; runtime registration remains
fail-closed if independently corrupted data still contains a duplicate.

`SyncedProfileLibraryPolicy` validates the atomic encoded byte size before decoding, then validates
the schema version, collection counts, user-facing name lengths and normalized structure. A remote
rejection cannot replace or trim the local library. Local private-install data remains readable even
when it exceeds the newer sync envelope; writing that library to iCloud is withheld with visible
recovery state until it is eligible. Replacing a rejected remote value is a separate explicit user
action and never occurs as a side effect of a failed pull.

### Local to one Mac

The active/manual profile selection, automatic trigger mappings, runtime active-workspace state,
the selected Quick App identity for each profile, monitor fingerprints, role-to-physical-monitor
bindings, trackpad preferences, Shortcut Guide enablement/size/position, focused-window border
preferences and per-application radius overrides, versioned onboarding progress/completion,
Accessibility state, login-item state, diagnostics, and live window
session remain local. `WorkspaceStateStore` writes the current WindowServer-bound session beneath
the user's cache directory using an atomic replacement. This includes exact hidden Quick App
identities only when WindowRanger hid those windows' applications. A changed WindowServer session
invalidates exact window IDs and that ownership marker rather than guessing. Legacy minimized-window
markers decode without granting application-unhide ownership.

The Stable/Beta update-channel choice and Sparkle automatic-check/download choices also remain
local to one Mac. Build-time Info.plist values decide whether the signed app is eligible to update,
which HTTPS appcast it may read, and which public EdDSA key verifies archives. Dev builds fail closed
before constructing Sparkle's updater, regardless of saved preferences. Stable clients allow only
Sparkle's default channel; Beta opt-in adds `beta`, while retaining default-channel eligibility.

Automatic profile resolution is pure and ordered: manual pin, foreground full-screen Game Mode
eligible session, exact display topology, portable dock state, local default, then safe fallback.
The local Game Mode mapping consumes the engine session only when the foreground full-screen game's
bundle explicitly declares `LSSupportsGameMode`; macOS exposes no supported API for reading the user's live per-game Game Mode
override. Ending that session re-runs the ordinary rules rather than restoring a remembered profile.

Portable profile transfer serializes only reusable profile definitions into a separately versioned
JSON transport document. Import validates the complete document, remaps every internal identity,
previews deterministic additive names, and performs one profile-library mutation without activation.
The transport file never becomes a second authoritative configuration source.

Settings exposes this ownership boundary directly. Profiles owns the reusable library, inline
profile name/icon editing, and explicit activation; Profile Switching owns this Mac's local selection rules; Displays owns the selected
profile's display mode and role definitions alongside this Mac's physical display bindings.
Workspaces, Displays, Applications, and Quick App Shelf share an explicit Settings edit target.
Selecting, creating, or duplicating a library profile changes only that edit
target; mutations are persisted into that reusable definition and do not publish live engine values
unless the target is active. The full-row sidebar selector changes only that edit target; **Use
Profile** remains in Profile Status as the explicit local manual-pin and engine activation boundary.
Menu Bar exposes the separate profile-owned display-role icons alongside
its global presentation controls, while Focus Border owns local application-specific appearance
overrides. Removing an App Rule or converting it to a Quick App never deletes the independent local
border override for that bundle identifier.

## Displays and recovery

Synced profiles refer to abstract roles; local fingerprints resolve them conservatively. A missing
or ambiguous physical display falls back safely without rewriting the synced home. Reconnect can
therefore restore the original role.

Sleep/wake and display notifications are coalesced through generation-tokened reconciliation.
AppKit workspace signals cover system/display sleep and fast-user switching; the distributed macOS
screen-lock and screen-unlock notifications provide the separate ordinary-lock boundary that those
workspace signals do not guarantee. Every observed suspension source must receive its matching
resume signal before reconciliation begins. Because Accessibility windows can disappear just before
the distributed lock notification arrives, a successful-empty collapse spanning at least half of
multiple still-running tracked applications receives a 500-millisecond grace period. Single-app
closure remains immediately authoritative; a coordinated collapse that remains fully active after
the grace period is accepted. While a native fullscreen window remains present in the current AX
snapshot, the same coordinated collapse stays non-authoritative without making fullscreen a global
layout suspension; ordinary management on another display continues. Accessibility snapshot
authority is per application rather than per display, so the successfully empty process cohort is
protected WindowServer-wide while currently enumerated windows remain write-eligible. A latched but
currently absent fullscreen session cannot prolong this protection indefinitely. Fullscreen exit
starts one fresh bounded grace so the returning Space can publish a stable snapshot before any
retained tree is pruned. Display topology resolves first, fresh AX elements are acquired second, and
visibility/layout is applied once the snapshot is stable. Bounded retries handle temporarily
incomplete enumeration.
After the layout solve, expected Tiled and Accordion frames are read back because a successful AX
write does not prove that the receiving app retained it. Only mismatched, still-eligible split
windows are retried, for a bounded number of attempts; a newer lifecycle signal supersedes the
verification, and full-screen, deferred, floating, and disappeared windows remain outside it. Old
focus/layout callbacks are superseded and cannot act on the newer generation.

Display snapshots begin with AppKit's current `visibleFrame`. A locally read Dock preference then
controls only the configured Dock edge: a visible Dock keeps AppKit's exclusion, while an auto-hidden
Dock restores that edge to the full screen frame. Other safe-area exclusions remain authoritative.
The preference is sampled with each display refresh so game transitions and Dock setting changes
invalidate the existing layout signature and reflow without a restart.

On graceful quit, persistent assignment state is saved before managed windows are returned to
visible frames. A debugger Stop or crash cannot run synchronous cleanup; startup reconciliation is
the recovery boundary for those cases.

The profile-aware Quick App Shelf is an engine-owned coordinated set of temporary presentation
overrides. Direction, size fraction, animation, Accordion or Carousel style, and a one-to-four
visible application maximum are profile-owned shelf presentation, applied uniformly to every
ordered application entry before engine publication. Each visible application contributes every
eligible admitted standard window from its one running process. Carousel divides the shelf's
cross-axis into non-overlapping window cards; Accordion overlaps windows along that axis while
leaving a fixed reachable edge and raising the selected window. The selected application retains
the existing bounded launch path, but presentation never launches extra apps merely to fill the
visible maximum. The synced shelf order and machine-local selected identity
are separate state: configuration publication cannot reorder the shelf or cancel an unchanged
entry's in-flight launch. Direct Command Palette selection means idempotent Show, the regular
shortcut means Toggle selected, and Previous/Next traverse the stable configured order. Launch,
show, hide, focus-loss, switching, removal, profile changes, screen suspension, and native-tab
replacement are generation-gated through one serialized transition path; a rapid switch retains
only the latest valid requested selection.

Exact ownership remains per window, while Hide confirmation and the ordinary toggle transition are
per application. One exact window owns focus. Selecting any already visible window promotes it
without collapsing or relaying out the group. Moving beyond the visible application group safely
hides the current applications, then presents the requested application and every eligible window
from whichever configured neighbours fit the new group. A second process for one configured bundle
fails closed without disturbing valid application groups.

Command Palette presentation is an explicit shelf-focus lease. Activating WindowRanger for that
panel does not count as external focus loss, palette-owned launches do not activate the target app,
and completed shelf previews retain palette keyboard focus. While an entry is presented, the normal
Previous Window and Next Window commands traverse windows inside the selected application before
continuing through the shelf's configured application order.
Navigate-arrow commands use the presented group geometry to choose the nearest visible Shelf window
in that direction. Arrow promotion raises and focuses that already-presented window in place without
rotating membership or relaying out the group, so reversing direction returns to the window just
left. At the end of the Shelf's layout axis it wraps to the opposite visible edge; perpendicular
arrows remain contained rather than falling through to a managed workspace window. Closing the
palette restores exact focus to a
presented shelf window only when that Shelf application was
frontmost before the palette opened. A merely retained Shelf session stays in its existing
visibility state while focus returns to the application that actually preceded the palette.
Activating any unrelated application still ends ordinary shelf presentation.

Managed workspace Navigate-arrow focus uses the nearest eligible spatial neighbour on the current
workspace and interaction display. When that direction has no neighbour, it wraps to the far edge
in the opposite direction, preferring perpendicular-axis overlap before distance. The fallback
never broadens candidate admission or crosses a workspace or display boundary.

Each entry resolves every eligible admitted window from one process for the configured bundle. The
group targets the pointer/interaction display's usable bounds. Its optional Top, Bottom, Left, or
Right movement uses generation-gated
frame steps so a hide, profile switch, sleep, termination, or newer toggle supersedes delayed
animation writes. Every direction expands from or collapses to a one-point frame inside the chosen
usable edge. No animation path travels through off-screen coordinates, and the receiving
application's Accessibility position transition is suppressed around direct frame writes. Once
owned, every shelf window is
excluded from normal visibility, layout, focus-cycle, reset, manual-geometry reconciliation, and
background-signature participation. The engine uses AppKit Hide/Unhide for the configured
application while retaining exact per-window geometry and restore targets. This avoids
the Dock minimize/restore transition, but intentionally means every window belonging to that
application follows its hidden state. Hide and Unhide are generation-gated and confirmed before the
session changes state. The engine preserves every exact target's durable restore frame and unhides
only application state it owns before that entry is removed, configuration/profile changes, and
lifecycle cleanup. It also
ignores its own programmatic activation when deciding whether another app has taken focus. A
successful AX snapshot
may replace an exact window identity during a native tab switch. The engine rebinds the session only
when the old key disappeared and exactly one newly tracked, same-process, same-bundle eligible
replacement exists. Other retained members of the application group do not make that one-for-one
handoff ambiguous. That replacement inherits the old local workspace, restore frame, display
placement, and layout metadata before background layout runs. Multiple new, pre-existing,
cross-process, or unrelated replacements leave the exact-window safety boundary intact.
When the local focused-window border is enabled, Quick App presentation bounds reuse the border's
four-point screen-edge clearance before applying the configured size fraction. Startup, wake,
native-tab replacement, hide-failure restoration, and ordinary presentation all use those same
bounds. Toggling the border while Quick App is presented supersedes any animation and reapplies the
final frame without changing focus or session ownership.
When a shortcut finds no eligible configured-app window, the engine asks Launch Services to open
and activate that application so its normal reopen handling can create a window, then starts one
generation-bound watchdog. Window discovery during that watchdog performs no Accessibility writes,
so the first eligible same-process window group can become the exact Quick App session before
ordinary workspace layout moves it. The watchdog checks eight times after a short launch delay, then
fails with explicit feedback; a profile change, shutdown, newer launch generation, missing
installation, launch error, timeout, or multiple matching processes never grants permission to
guess a target.
During startup reconciliation, the engine establishes ownership only for configured shelf entries
before initial workspace visibility and layout. Every configured entry whose eligible windows come
from one process is claimed hidden, regardless of pre-launch visibility; launching WindowRanger
never implicitly presents a Shelf entry. Crash-restart recovery may reclaim a hidden application
only when the WindowServer-bound marker matches the exact owned window identities and bundle and
AppKit still reports that application hidden. Same-bundle candidates from multiple processes remain
untouched. Newly admitted same-process windows join the exact application group, and an
authoritatively removed member leaves only that exact ownership set; native-tab state transfer still
requires the existing exact same-process replacement proof.

## UI and focus safety

The menu bar never assigns an `NSStatusItem.menu`, because AppKit gives an assigned menu ownership
of every click. Compact, Medium, and Full on macOS 14–26 use one stable custom interaction view: a
primary click outside an explicit Full workspace button, any secondary click, or the primary
accessibility action presents the same `NSMenu`, while an explicit workspace-button primary click
switches. macOS 27 treats one custom status-item view as one interaction target and rewrites nested
clicks to that target, so every mode uses one standard status item per logical display group.
Compact adapts to the configured label mode: keys use symbol-specific safe areas inside the
horizontal, portrait, laptop, and combined-display symbols, while names render as compacted bare
text beside a smaller symbol, with no status dot or enclosing badge. A
hidden display icon falls back to bare workspace text. Medium renders its active-workspace chip
inside that button; every action opens the shared menu. Settings
embeds these same production display-group content views on macOS 27 rather than maintaining a
separate visual imitation. Full workspace segments remain noninteractive visuals;
the owning status button receives one action and resolves a primary click by comparing the public
global pointer X with those segments' live screen-space frames. Display, overflow, unresolved,
right-, Control-, and accessibility actions present the shared menu. The standalone primary item is
hidden in this grouped mode because every display group is already a safe menu target. Display-group
items are retained across presentation changes and are added or removed only when display topology
changes. Full workspace segments expose an
immediate visual hover state. On macOS 14–26 each native workspace button owns its standard tracking
area; on macOS 27 the standard parent status button owns workspace-shaped tracking regions and
resolves enter/exit with the same global screen-space geometry as clicks. This compatibility path
does not add event monitors, access the system menu-bar process, or change gesture exclusivity.
After a short dwell, the menu-bar controller may attach a nonactivating application shelf beneath
the hovered workspace. The shelf reads an asynchronous, read-only application summary from the
workspace engine's existing managed-window state; it does not enumerate Accessibility windows or
perform writes merely because the pointer hovered. Applications are grouped by normalized bundle
identifier, with a process fallback for bundle-less apps, and the workspace's focus history chooses
the representative window before stable layout order. Selecting a shelf row returns one target to
the engine, which performs the normal workspace transition and filters its existing verified focus
pipeline to that application. If the target disappeared, the operation leaves focus neutral instead
of selecting a different app. Keep-on-all-workspaces apps are omitted because the shelf describes
direct workspace membership. The shelf embeds its content in AppKit's native regular Liquid Glass
surface on macOS 26 and later, with the system menu material as the older-OS fallback. It enables a
vertical scroller only when the bounded eight-row viewport actually overflows; the empty state and
ordinary app lists do not advertise scrolling. Returning from the shelf to the macOS 27 status item
crosses a small non-window gap where AppKit may omit a new tracking-area enter. During the existing
dismissal grace, the controller therefore performs one delayed re-sample through the display
group's existing global-pointer resolver. A resolved workspace restores the normal hover state and
cancels dismissal; an unresolved pointer changes nothing. This remains a bounded transition check,
not a pointer monitor or polling loop.
Display snapshots retain their hardware-derived built-in, external, or combined icon kind. Each
synced profile display role owns one menu-bar icon style; the active profile's local conservative
role binding resolves that style to a live physical display. Unbound roles, ambiguous role bindings,
and two explicit roles bound to one display fall back to Automatic instead of guessing. The
resolved per-display configuration is injected into Compact, Medium, the pre-macOS-27 Full strip,
macOS-27 Full display groups, Settings preview, and pressure calculations. Automatic derives the
symbol from the bound display kind. Explicit horizontal-monitor, vertical-monitor, and laptop
choices replace only that role's resolved display symbol; None omits both its icon view and
pressure-budget gap. Unified mode retains its combined Automatic icon because its one logical block
does not map to a physical role. Workspace hit targets, accessibility display names, display
ordering, and status-item ownership do not depend on this cosmetic choice.
Command feedback
is a nonactivating click-through overlay. On macOS 26 and later its content is embedded in AppKit's
public static Liquid Glass view; older supported releases use the system HUD material. Both
surfaces use a capsule radius derived from the live overlay height. The surface choice never changes
its panel, focus, input, timing, or accessibility boundary.

Manual Tiled divider resize and title-bar move use two-phase preview transactions. A passive global
mouse monitor asks the serialized engine for the focused-window frame only until a genuine size or
position change classifies the gesture. The engine then freezes the committed tree, captures every
participant's exact original frame, and parks only those windows at the recoverable desktop edge.
Resize sessions also retain the dragged edge and pointer anchor; subsequent samples at a bounded
30 Hz project an observed frame from the pointer rather than the concealed AX window. Move sessions
resolve the tile under the pointer against the immutable committed frames, swap only those two tree
leaves, and animate every changed glass frame toward the proposed result. Neither path requires
broad window enumeration or application-wide Hide. A status-level, nonactivating, click-through
overlay draws untinted clear Liquid Glass tiles over the visible desktop on macOS 26 or later. The
glass remains in one shared `NSGlassEffectContainerView`; its only content is a fine inset outline.
Older supported systems use the HUD-material fallback on the same transparent panel. The
focused-window border is suppressed for the transaction so only the landing hints remain. Mouse-up
revalidates profile, workspace, participant set, display topology, layout configuration and original
tree, snaps the parked windows directly into the latest proposed frames, persists the committed
tree, and then removes the overlay. Releasing a move over its source or a gap restores the original
frames. Cancellation also restores those captured frames before dismissing the preview. Pause,
Shelf presentation, full-screen protection, lifecycle suspension, display change, WindowServer
replacement and quit all cancel the tokened preview; stale dismissals cannot remove a newer preview.

The optional Shortcut Guide separately observes
paired global and local `flagsChanged` events without consuming them. The exact configured Navigate
and Arrange families select content from the same conflict-checked registry Carbon uses; changing a
family refreshes both Carbon registration and passive observation. Incompatible extra modifiers, conflicts and registration
failures produce no misleading entries. Its panel never becomes key or main, never activates the
app, follows the engine's resolved interaction display, and uses macOS 26 Liquid Glass with the
system HUD material as the older-system fallback. The normal presentation remains one low, wide
key map. Presentation-only groups label the action and its workspace, window, layout, or display
target without maintaining a second command list; the spatial arrow caption is centred below its
keys. Unusually dense valid configurations add rows rather than clipping actions. Enablement,
Small/Medium/Large density and the nine screen anchors are local to one Mac. When a Quick App Shelf
session is presented, the engine exposes only its direction and display as a read-only guide
context. The normal conflict-checked Navigate content is then filtered to commands that remain
truthful for Shelf focus: workspace switching and Commands remain, the Shelf toggle becomes Hide
Shelf, ordered traversal names Shelf windows, and spatial focus retains only the Shelf layout axis.
The view uses one lower density and the screen edge opposite the Shelf; a held guide refreshes when
the Shelf opens or closes. Arrange content is suppressed because ordinary focused-window
arrangement does not act on a Shelf-owned window. The Focus Border remains independent. Shortcut
recording, protected game sessions, sleep, inactive login sessions, display changes and termination
stop the passive monitor and clear the panel so a missed modifier release cannot leave it visible.

The optional focused-window highlight
uses the same nonactivating, click-through boundary, polls only while enabled on this Mac, and excludes
WindowRanger-owned windows, apps identified as games through the same public bundle metadata used by
full-screen safety, and full-screen windows. Its local white-by-default colour is independent of the
synced menu-bar accent. Automated Tiled and
Accordion geometry reserves a four-point screen-edge clearance while it is enabled; Freeform
geometry remains untouched. Optional Tiled-only and multiple-window filters consume the engine's
managed-window workspace snapshot; if a requested workspace condition cannot be proven, the border
stays hidden. Border corner radius resolves from a conservative OS-generation policy, then an
optional normalized bundle-identifier override wins. AppKit, Accessibility, and WindowServer do not
publish another app's rendered corner radius, so the generation table uses verified values only and
keeps the macOS 27 baseline for later releases until a future design change is verified. Per-app
overrides are local appearance state rather than synced App Rule actions because the correct
rendering depends on this Mac and OS. Their lifetime is independent of profile App Rules and Quick
Apps. The Command Palette captures its external target before
becoming key and rejects a selection if that window/workspace/display/profile token changed while
the user typed. Every command revalidates while the palette's external-focus lease is still active;
ordinary commands then dismiss, restore the previous application, and dispatch, while exact
placement is validated and enqueued before dismissal. A top segmented control shows
the captured workspace's Freeform, Tiled, or Accordion layout. It dispatches through the same typed
command path and keeps the palette open; an observable presentation context adopts each accepted
layout token so repeated changes remain valid. A selection made after an inline layout change is
revalidated against a fresh context; a placement command may adopt the settled placement token only
when the exact window, workspace, layout, display topology, and profile identity are unchanged.
Every genuinely different target still fails closed. For an eligible app owning the captured focused
window, the same context exposes its active profile's App Rule and App Shelf membership. The add
commands carry the captured workspace and active-profile identity through dispatch, mutate only the
active profile, and fail closed if profile selection, membership, or Shelf capacity changes before
the MainActor write. An App Shelf conversion first proves capacity so it cannot discard an App Rule
when all four Shelf entries are occupied. Exact placement is revalidated and enqueued
while the palette still owns a preserved managed-window anchor; a transient nil AX focus during
dismissal retains that anchor. The engine's serial queue commits placement before palette dismissal
ends Shelf preservation or restores a Quick App Shelf window or fallback application. The command
results, workspace layout, and focused-window placement remain separate interaction
regions. A compact Quick Actions block stacks workspace layout above conditional window placement.
Tab enters that block; Up from the first command result enters its visually adjacent bottom row,
then Up and Down change rows, while Left and Right change layout only on the workspace row. Return
on the placement row opens the inline Placement Halo in a separate
palette-owned keyboard mode whose arrows traverse only validated position previews. The placement
row is omitted when that provider is empty. Escape collapses the halo or restores command-result
handling. A nonempty query hides Quick Actions and collapses the Halo until search is cleared.
Legacy standalone-wheel preferences remain decodable for compatibility. The superseded Globe/Fn
preference, gesture state and event-monitor implementation are absent; Command Palette activation
uses the same Navigate-family registry as every other global shortcut.

Pause is an AppDelegate-owned transient runtime state backed by a defensive engine write gate. Its
hotkey registration scope admits only the Command Palette owner, and the paused palette indexes only
the explicit Resume command. Workspace swipe and Shortcut Guide keep independent suppression reasons.
The engine timer continues read-only discovery so full-screen-game exit and window membership remain
current, while frame, position, Quick App animation, wake, activation, and visibility writers fail
closed. Resume refreshes with `performAXWrites: false` before clearing the gate; this deliberately
skips tiled drag/resize reconciliation, then applies current visibility/layout once. A profile
activation published during Pause is retained as the newest generation and transitions before any
stale-profile reconciliation.

Settings is an explicit app-owned floating utility: it may activate and focus, but it is excluded
from third-party discovery, layout and persistence. Every explicit open captures the engine's
current virtual workspace and interaction display, updates the utility's assignment, and surfaces
the one existing window as key and frontmost. AppKit's `moveToActiveSpace` is evaluated when a window
is ordered in, so an already-visible Settings window is ordered out synchronously before it is
re-shown; this moves the same window to the active native Space instead of switching back to its old
one. Detached status-menu presentation first lets the originating status-item interaction complete:
standard display-group buttons dispatch on mouse-up, and every menu route schedules presentation on
the following main-loop turn. This prevents `NSMenu` from consuming the matching mouse-up inside a
nested tracking loop and leaving the original status control pressed. The Settings menu action then
records a pending request, but the explicit synchronous `NSMenu.popUp` call must return before that
request is consumed and the native Settings command is scheduled on another main-loop turn. Popup
menus own a nested event loop, so delegate close, tracking-end, and post-action notifications can all
arrive before the presentation call itself returns; none is a sufficient handoff boundary. The
action also does not call `cancelTracking()`. This keeps
accessory-app activation outside AppKit's entire popup-menu transaction and preserves Carbon global
hot-key delivery. Command-comma does not use that gate. Passive restoration when returning to its
assigned virtual workspace remains nonactivating. Carbon remains the global shortcut owner, and
shortcut recording clears its registrations until recording finishes. SwiftUI retains its Settings
window after a normal close, so the coordinator retains only its weakly backed surface adapter and
can reopen that exact window directly on the next explicit request. If SwiftUI actually releases the
window, the unavailable adapter is discarded and the supported scene-opening action is used again.

Workspace swiping is a separate off-by-default, machine-local hardware preference. Its AppKit/Core
Graphics adapter is isolated behind an injected monitor and feeds a pure state machine only touch
identities and normalized positions for the current gesture. The state machine requires the selected
three or four fingers to move coherently and horizontally past one threshold, then latches until the
gesture ends so it cannot emit multiple commands. The adapter returns every event unchanged, retains
no touch history after the gesture, and fails closed if macOS does not expose the generic gesture
stream. Accepted swipes use `cycleWorkspace`, preserving its ordered wraparound and Independent
Displays interaction routing. Sleep, inactive login sessions, foreground declared games,
full-screen games, Pause, shortcut recording, display changes, and profile transitions cancel or suspend
observation.

Exact focus operations use bounded activation/focus/raise verification and generation tokens. For an
inactive target application, the engine prepares the exact window before setting the public
application-level Accessibility frontmost attribute. Candidate workflows decide success from the
observed result rather than the setter return: if the app remains inactive, one explicit AppKit
activation fallback is allowed before at most one exact-window retry. A genuine competing or ignored
focus aborts the transaction. One-shot focus paths that do not advance through candidates retain the
immediate AppKit compatibility fallback only when Accessibility rejects the frontmost write.
An ordinary layer-0 standard window with read-only focus attributes remains a candidate only when it
reports itself as both its application's focused and main window and supports raising; the same exact
WindowServer verification must still succeed after activation. Read-only windows without that local
identity remain excluded. An already tracked, visible standard window may transiently report a
negative WindowServer layer before its first post-restart activation. It remains a candidate only
when it exposes a writable Accessibility focus route and supports raising. Positive-layer surfaces,
negative-layer dialogs, and negative-layer read-only windows remain excluded.
Already-active applications remain on the exact-window-only path. Verification normally requires the
exact Accessibility focused-window identity. When that value is temporarily absent, it accepts the
target only if the application is active and WindowServer independently reports that exact layer-0
window as the application's first front-to-back entry; a higher-layer window from the same app
invalidates the proof. A different Accessibility window still wins as competing or mismatched
evidence. Once a focus transaction succeeds, it may forward that already-known target to the
focused-window border as observation only. The border revalidates that the application remains
active and the exact target retains that WindowServer proof on every poll, then discards the handoff
when Accessibility catches up, either proof changes, or its three-second lease expires. It retains
the existing fullscreen and workspace-filter checks.
Programmatic focus intent is separated from genuine user competition so stale notifications do not
bounce work back to another display or workspace.

## Safety invariants

- Never write a window frame before central admission and current-context validation.
- Never focus a parked, ignored, off-workspace or wrong-display candidate.
- Never rewrite a synced display home because a monitor is absent or ambiguous.
- Never treat window IDs as durable across WindowServer sessions.
- Never let conflicting hotkeys silently assign ownership to the first command.
- Never let unit tests instantiate AppDelegate or production system integrations.
- Never report live validation, notarization or distribution as complete from automated tests alone.
