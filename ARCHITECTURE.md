# WindowManager architecture

> **Pre-release:** WindowManager is a provisional project name. This document describes the
> current private development build; it is not a compatibility or public API contract.

WindowManager is a native macOS menu-bar application that implements virtual workspaces without
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

The non-hosted `WindowManagerTests` target compiles shared sources directly and excludes
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

## Persistence boundaries

### Synced reusable definitions

The profile library can sync through iCloud key-value storage. A profile contains workspace
definitions/order/keys/layout geometry, Unified or Independent display mode, abstract display roles,
workspace-role assignments and typed app rules. Global preferences such as menu-bar presentation,
general command shortcuts and command-wheel configuration use their existing global settings path
and are not profile content.

### Local to one Mac

The active/manual profile selection, automatic trigger mappings, runtime active-workspace state,
monitor fingerprints, role-to-physical-monitor bindings, Accessibility state and live window session
remain local. `WorkspaceStateStore` writes the current WindowServer-bound session beneath the user's
cache directory using an atomic replacement. A changed WindowServer session invalidates exact window
IDs rather than guessing.

## Displays and recovery

Synced profiles refer to abstract roles; local fingerprints resolve them conservatively. A missing
or ambiguous physical display falls back safely without rewriting the synced home. Reconnect can
therefore restore the original role.

Sleep/wake and display notifications are coalesced through generation-tokened reconciliation.
Display topology resolves first, fresh AX elements are acquired second, and visibility/layout is
applied once the snapshot is stable. Bounded retries handle temporarily incomplete enumeration.
Old focus/layout callbacks are superseded and cannot act on the newer generation.

On graceful quit, persistent assignment state is saved before managed windows are returned to
visible frames. A debugger Stop or crash cannot run synchronous cleanup; startup reconciliation is
the recovery boundary for those cases.

## UI and focus safety

The menu bar uses one stable AppKit status item. Its primary target always opens the app menu; only
explicit Full-mode workspace buttons switch. Command feedback is a nonactivating click-through
overlay, while the radial command wheel is nonactivating until a validated action is committed.
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
