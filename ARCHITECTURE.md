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
| Menu bar and command wheel | `Sources/MenuBar`, `Sources/RadialMenu` | Context presentation and dispatch through the same typed command layer used by hotkeys. |
| Diagnostics | `Sources/Diagnostics` | Structured privacy-filtered Debug traces with bounded rotation and no-op/test sinks. |

The non-hosted `WindowRangerTests` target compiles shared sources directly and excludes
`Sources/App`. It therefore tests the model and injected boundaries without starting AppDelegate,
installing production hotkeys, asking for Accessibility permission or moving live windows.

## Runtime data flow

1. `AppDelegate` creates `SettingsStore`, `WorkspaceEngine`, the shared command dispatcher,
   presentation controllers and `HotKeyManager`.
2. `SettingsStore` loads one versioned synced `ProfileLibrary` plus machine-local
   `ProfileLocalState`, then resolves abstract display roles against connected local displays.
3. `WorkspaceEngine.start()` checks Accessibility trust, enumerates applications/windows and sends
   each candidate through the central admission classifier before it can enter any other subsystem.
4. Hotkeys, the optional local workspace-swipe monitor, the menu bar and the command wheel emit
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

## Window admission and precedence

`AccessibilityWindow.admissionDecision` is the sole discovery boundary. It produces one of four
dispositions: normal managed window, managed dialog (automatically floating), temporarily
ineligible, or ignored transient/popup. Ignored objects never enter membership, layout, persistence,
focus cycling or recovery. The verified non-normal-layer Codex pet/panels are excluded here rather
than patched out later.

Built-in compatibility profiles are versioned, declarative corrections for verified application
surfaces. A profile matches a normalized bundle identifier plus only the role, subrole, layer,
modal, control-presence, or move/resize evidence needed to distinguish that surface. It produces an
ordinary admission disposition and records the matched profile identifier in diagnostics. Profiles
must be backed by a privacy-safe fixture and must not encode a user's workspace assignment or layout
preference. The bundled registry is intentionally local to the signed app; there is no remotely
updated exception list.

Effective layout participation follows this order:

1. a narrowly matched built-in compatibility profile can correct the surface's admission;
2. generic admission classifies every unmatched window;
3. ignored/transient or temporarily unsafe windows are untouched;
4. a user App Rule that excludes layout remains authoritative for admitted windows;
5. explicit per-window floating state controls otherwise eligible normal windows;
6. high-confidence dialog classification automatically floats a dialog;
7. remaining windows participate in the workspace's Freeform, Tiled or Accordion behavior.

Keep-on-all-workspaces rules affect visibility but do not grant a window permission to enter layout
or focus scopes that it otherwise fails.

Debug admission evidence is deliberately richer than the active classifier. The cached snapshot
distinguishes authoritative, unsupported, and unavailable modal, focused, main-window, window-control,
position-settable, and size-settable observations so representative real-app fixtures can justify a
later rule change. The regular engine poll retains cached support evidence rather than performing
these extra queries every 0.75 seconds. The exceptions are a surface whose bundle and ordinary
role/subrole/layer/control evidence already match a compatibility profile that explicitly requires
support-only evidence, and a layer-0 standard window with a Close control but no Full Screen control
whose move/resize capability evidence is not yet authoritative. Only those candidates are enriched
before classification. A movable standard candidate that authoritatively cannot resize floats as a
managed dialog; unavailable or unsupported evidence leaves it conservatively managed as normal.
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

The profile library can sync through iCloud key-value storage. A profile contains workspace
definitions/order/keys/layout geometry, Unified or Independent display mode, abstract display roles
and their menu-bar icon styles, workspace-role assignments, typed app rules, and an optional
Quick App bundle identifier/display name/presentation. Normalization makes Quick App ownership
mutually exclusive with an App Rule for the same bundle identifier. Global preferences
such as menu-bar presentation, general command shortcuts and command-wheel configuration use their
existing global settings path and are not profile content.

`SyncedProfileLibraryPolicy` validates the atomic encoded byte size before decoding, then validates
the schema version, collection counts, user-facing name lengths and normalized structure. A remote
rejection cannot replace or trim the local library. Local private-install data remains readable even
when it exceeds the newer sync envelope; writing that library to iCloud is withheld with visible
recovery state until it is eligible. Replacing a rejected remote value is a separate explicit user
action and never occurs as a side effect of a failed pull.

### Local to one Mac

The active/manual profile selection, automatic trigger mappings, runtime active-workspace state,
monitor fingerprints, role-to-physical-monitor bindings, Accessibility state and live window
session remain local. `WorkspaceStateStore` writes the current WindowServer-bound session beneath
the user's cache directory using an atomic replacement. A changed WindowServer session invalidates
exact window IDs rather than guessing.

Portable profile transfer serializes only reusable profile definitions into a separately versioned
JSON transport document. Import validates the complete document, remaps every internal identity,
previews deterministic additive names, and performs one profile-library mutation without activation.
The transport file never becomes a second authoritative configuration source.

## Displays and recovery

Synced profiles refer to abstract roles; local fingerprints resolve them conservatively. A missing
or ambiguous physical display falls back safely without rewriting the synced home. Reconnect can
therefore restore the original role.

Sleep/wake and display notifications are coalesced through generation-tokened reconciliation.
Display topology resolves first, fresh AX elements are acquired second, and visibility/layout is
applied once the snapshot is stable. Bounded retries handle temporarily incomplete enumeration.
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

The profile-aware Quick App is an engine-owned temporary presentation override. It resolves only
one unambiguous admitted standard window for the configured bundle and targets the pointer/interaction
display's usable bounds. Its optional Top, Bottom, Left, or Right movement uses generation-gated
frame steps so a hide, profile switch, sleep, termination, or newer toggle supersedes delayed
animation writes. Top expands from a collapsed frame at the usable top edge because macOS clamps
ordinary app windows positioned above the menu bar; the other directions slide from beyond their
screen edge. Once selected, the window is
excluded from normal visibility, layout, focus-cycle, reset, manual-geometry reconciliation, and
background-signature participation. The engine parks it while hidden, preserves its durable restore
frame, restores it before configuration/profile changes and lifecycle cleanup, and ignores its own
programmatic activation when deciding whether another app has taken focus.

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
its panel, focus, input, timing, or accessibility boundary. The optional focused-window highlight
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
rendering depends on this Mac and OS. The radial command wheel is nonactivating until a validated
action is committed.

The optional Globe/Fn wheel trigger keeps observation and filtering on separate safety boundaries.
A passive session tap observes modifier, keyboard, mouse-button, and system-defined competition and
can never delay or divert those events. A dedicated user-interactive run loop owns the narrow active
tap; its callback fast-passes every ordinary key and can discard only the synthetic native Globe
action while an accepted hold has armed that one suppression. macOS timeout or user-input disablement
stops the monitor and fails open rather than re-enabling it. Foreground applications identified as
games through public bundle metadata suspend the Globe/Fn and workspace-swipe monitors even when
their window is borderless; this does not broaden the native-fullscreen geometry guard.

Settings is an explicit app-owned floating utility: it may activate and focus, but it is excluded
from third-party discovery, layout and persistence.

Workspace swiping is a separate off-by-default, machine-local hardware preference. Its AppKit/Core
Graphics adapter is isolated behind an injected monitor and feeds a pure state machine only touch
identities and normalized positions for the current gesture. The state machine requires the selected
three or four fingers to move coherently and horizontally past one threshold, then latches until the
gesture ends so it cannot emit multiple commands. The adapter returns every event unchanged, retains
no touch history after the gesture, and fails closed if macOS does not expose the generic gesture
stream. Accepted swipes use `cycleWorkspace`, preserving its ordered wraparound and Independent
Displays interaction routing. Sleep, inactive login sessions, foreground declared games,
full-screen games, shortcut recording, display changes, and profile transitions cancel or suspend
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
identity remain excluded.
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
