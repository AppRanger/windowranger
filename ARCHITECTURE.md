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
4. Hotkeys, the menu bar and the command wheel emit `WindowManagerCommand` values through one
   dispatcher. The engine validates current context again before applying a mutation.
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

Effective layout participation follows this order:

1. ignored/transient or temporarily unsafe windows are untouched;
2. an app rule that excludes layout remains authoritative;
3. explicit per-window floating state controls otherwise eligible normal windows;
4. high-confidence dialog classification automatically floats a dialog;
5. remaining windows participate in the workspace's Freeform, Tiled or Accordion behavior.

Keep-on-all-workspaces rules affect visibility but do not grant a window permission to enter layout
or focus scopes that it otherwise fails.

The Add Application Rule picker reads existing engine membership without refreshing or mutating
windows. Open apps are presented separately from other installed apps. A new rule inherits a live
workspace only when every currently managed window for that bundle agrees on one workspace;
windowless or split-workspace apps retain no assignment so Settings never guesses a bundle-wide
rule from ambiguous per-window state.

## Persistence boundaries

### Synced reusable definitions

The profile library can sync through iCloud key-value storage. A profile contains workspace
definitions/order/keys/layout geometry, Unified or Independent display mode, abstract display roles,
workspace-role assignments and typed app rules. Global preferences such as menu-bar presentation,
general command shortcuts and command-wheel configuration use their existing global settings path
and are not profile content.

`SyncedProfileLibraryPolicy` validates the atomic encoded byte size before decoding, then validates
the schema version, collection counts, user-facing name lengths and normalized structure. A remote
rejection cannot replace or trim the local library. Local private-install data remains readable even
when it exceeds the newer sync envelope; writing that library to iCloud is withheld with visible
recovery state until it is eligible. Replacing a rejected remote value is a separate explicit user
action and never occurs as a side effect of a failed pull.

### Local to one Mac

The active/manual profile selection, automatic trigger mappings, runtime active-workspace state,
monitor fingerprints, role-to-physical-monitor bindings, Accessibility state and live window session
remain local. `WorkspaceStateStore` writes the current WindowServer-bound session beneath the user's
cache directory using an atomic replacement. A changed WindowServer session invalidates exact window
IDs rather than guessing.

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

## UI and focus safety

The menu bar uses one stable AppKit status item. Its primary target always opens the app menu; only
explicit Full-mode workspace buttons switch. Command feedback is a nonactivating click-through
overlay. The optional focused-window highlight uses the same nonactivating, click-through boundary,
polls only while enabled on this Mac, and excludes WindowRanger-owned windows, apps identified as
games through the same public bundle metadata used by full-screen safety, and full-screen windows. Its
local white-by-default colour is independent of the synced menu-bar accent. Automated Tiled and
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
Settings is an explicit app-owned floating utility: it may activate and focus, but it is excluded
from third-party discovery, layout and persistence.

Exact focus operations use bounded activation/focus/raise verification and generation tokens.
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
