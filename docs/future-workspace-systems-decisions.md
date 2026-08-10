# Future workspace systems — decision brief

Status: **Research only for pinned-display mode, named arrangements, the optional overview, and
reusable layout presets.** Section 4 also distinguishes those unapproved preset/editor ideas from
the Tiled placement and direct-manipulation behavior that is already implemented and tested.

This brief scopes four adjacent concepts without turning them into one feature. It preserves the
current product boundaries: profiles are reusable configuration rather than window snapshots;
Unified and Independent Displays remain the only built display modes; and layouts remain Freeform,
Tiled, and Accordion.

## Shared platform evidence

- AppKit exposes the current `NSScreen.screens` topology and posts a screen-parameters notification
  when it changes; Apple says the array must not be cached. `visibleFrame` is the current safe area
  excluding menu bar, Dock, and camera housing, and also must not be cached. ([screens](https://developer.apple.com/documentation/appkit/nsscreen/screens), [visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe))
- Core Graphics can report before/after display-reconfiguration callbacks. Apple says display state
  is current in the post-change callback and removed IDs must no longer be queried. ([display reconfiguration callback](https://developer.apple.com/documentation/coregraphics/cgdisplayreconfigurationcallback))
- Accessibility exposes a window's global top-left position; WindowRanger already validates and
  writes position/size through its existing trusted boundary. ([`kAXPositionAttribute`](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute))
- ScreenCaptureKit can enumerate shareable displays/apps/windows and capture individual frames, but
  Apple requires an explicit Screen Recording permission request and usage description for capture.
  Apple's sample prompts on first use and requires restart after granting access. ([ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [`SCShareableContent`](https://developer.apple.com/documentation/screencapturekit/scshareablecontent), [`SCScreenshotManager`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager), [macOS capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos))
- AppKit supports native in-app drag/drop and read-only systemwide event monitoring. A global monitor
  observes rather than modifies other apps' events; key monitoring requires Accessibility trust.
  App-owned overlay windows can be made transparent to mouse input. ([SwiftUI drag/drop](https://developer.apple.com/documentation/swiftui/adopting-drag-and-drop-using-swiftui), [global event monitor](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29), [`ignoresMouseEvents`](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents))

## 1. Pinned-display mode

### Product distinction and value

A pinned-display mode would be a third mode, not an alias for Independent Displays. Unified changes
one workspace across every participating display. Independent gives every display an independently
active workspace. The proposed mixed mode would switch a unified set of **staged** displays while
one or more **pinned** displays keep their current windows/workspace unchanged. A fixed chat,
monitoring, reference, or presentation display is the clearest use case. BetterStage documents this
general product pattern as pinned versus staged monitors; that is comparative evidence, not a spec
to copy. ([BetterStage monitor management](https://betterstage.app/docs/monitor-management))

### Model and persistence implications

- Candidate profile content: a display behavior for each **abstract display role** (`staged` or
  `pinned`) plus one active workspace for the staged group and one retained active workspace per
  pinned role.
- Physical monitor matching stays local through the existing conservative role bindings. A profile
  must never sync or persist a raw physical monitor ID.
- Runtime active-workspace state stays local, as it does for the current modes.
- A role's pinned/staged intent should not be rewritten when its physical display is missing.

### Interaction

Settings would need a topology/role editor that makes participation explicit before enabling the
mode. Menu-bar Compact/Medium/Full presentations must show which displays are pinned without making
informational chips switch workspaces. Workspace switch/move, profile transitions, command-wheel
destinations, and Settings routing need a single definition of the staged interaction scope.

### Failure and recovery

- A disconnected pinned role remains pinned in the profile but is absent from the live topology.
- Windows from the absent role use the current safe fallback without reclassifying the fallback
  display as permanently pinned; reconnect returns them to the role.
- If every connected role is pinned, workspace-switch commands need an explicit no-op explanation;
  the app must not silently choose main as a staged display.
- Ambiguous identical-monitor fingerprints remain unresolved rather than guessed.

### Dependencies and tests

Depends on the current abstract roles, fingerprints, topology reconciliation, menu-bar resolver,
profile transitions, and Independent-mode invariants. Pure tests would cover role resolution,
zero/one/many pinned roles, all-pinned rejection, disconnected/reconnected roles, ambiguous matches,
workspace moves, profile changes, wake, menu presentation, and no rewrite of synced intent.

### Product decisions still required

1. Is pinning profile-specific, or a local per-Mac overlay on every profile?
2. Can multiple displays be staged as one group, or is there exactly one staged display?
3. What should a workspace homed to a pinned role mean when switching the staged group?
4. Does clicking a pinned display in Full mode merely open a menu, or offer a deliberate unpin action?
5. Is an all-pinned configuration forbidden or a valid pause state?

## 2. Named whole-desk arrangements

### Product distinction and value

An arrangement would capture a recoverable **desired desk state** for the apps/windows that exist,
whereas a profile defines how WindowRanger behaves over time. Examples are “Writing session”,
“Customer call”, or “Presentation”. Applying one could place eligible current windows into chosen
workspaces/displays/layout slots. It must not turn transient AX/WindowServer IDs into durable data.

### Model and persistence implications

A conservative first model could contain stable app bundle IDs, abstract display roles, destination
workspace identities or semantic workspace names, layout choice/geometry, and optional per-app
placement slots. It should not contain window titles, document paths/URLs, raw monitor IDs, or exact
window IDs. That means multiple same-app windows cannot be matched perfectly without a new, explicit
privacy-sensitive identity policy.

It is unresolved whether arrangements belong inside a profile, form a separate synced library, or
remain local. A synced arrangement can reference profile workspace/role IDs only if its ownership
and deletion/migration rules are explicit.

### Interaction

Creation needs a preview of what reusable information will be saved. Apply should show a diff-like
summary, offer merge versus replace only if both semantics are deliberately specified, validate all
targets first, then run one generation-tokened transition with a bounded rollback/Undo record. The
command wheel could list arrangements later, but not before Settings makes scope and consequences
clear.

### Failure and recovery

- Missing apps/windows are reported and skipped; no stale identity is resurrected.
- Extra open windows need a settled retain/move/ignore policy.
- Minimized, full-screen, ignored, deferred, dialog, floating, keep-on-all, and app-rule precedence
  remains authoritative.
- Missing display roles use safe fallback without rewriting the arrangement.
- An interrupted apply must leave every managed window visible and recoverable, with the prior desk
  state available to Undo when identities are still valid in the same WindowServer session.

### Dependencies and tests

Depends on portable profile-style validation/remapping, profile transitions, reset/recovery,
transactional layout commits, app-rule precedence, and a native preview. Tests need multiple same-app
windows, missing/extra apps, rule conflicts, display fallback, changed WindowServer session,
mid-transaction rejection, Undo safety, and strict exclusion of titles/paths/raw IDs from coding and
diagnostics.

### Product decisions still required

1. Does apply only rearrange open windows, or may it launch applications?
2. Is matching by bundle ID sufficient, and how are multiple windows of one app ordered?
3. Are arrangements owned by one profile, global and synced, or local to a Mac?
4. Which data is captured: workspace membership, display role, layout mode, tree/order/weights,
   Freeform frames, floating overrides, and/or app-rule changes?
5. Are unmatched current windows retained, sent to an overflow workspace, or left untouched?
6. Is apply always additive/merge, always replace, or a previewed choice?

## 3. Optional visual workspace/stage overview

### Product value and feasible tiers

An overview could make workspace contents discoverable, support mouse-based switching, and provide a
safe drag target for sending managed windows. There are two materially different products:

1. **Metadata overview:** workspace/display names, app icons, counts, layout state, and privacy-safe
   window placeholders derived from the existing AX model. It needs no new capture permission.
2. **Live-thumbnail overview:** pixel thumbnails obtained through ScreenCaptureKit. This introduces a
   separate Screen Recording permission, usage copy, denial/retry/restart handling, captured-pixel
   privacy, memory/refresh policy, and a Release audit.

Because inactive workspace windows are parked rather than on-screen in a normal visible position,
live capture of every inactive window cannot be assumed reliable. The product must either show a
placeholder, cache a last-visible frame (with explicit privacy/lifetime rules), or avoid promising a
live thumbnail. It must never unpark or focus a window merely to make a preview.

### Model, interaction, and privacy

The overview itself should be ephemeral UI, not a profile snapshot. Drag payloads use internal
managed-window/workspace IDs only for the current session; drop validates the captured generation
and dispatches the existing send-only or move-and-follow command. Thumbnails, if approved, remain in
memory, are never synced/persisted/logged, and stop immediately on close, sleep, lock, permission
loss, or app quit.

Screen Recording must be opt-in from an explicit overview setting/action. It must not be requested
at startup, during tests, or just because Accessibility is granted. Denial falls back to the metadata
overview. The app must clearly distinguish Accessibility window control from captured window pixels.

### Failure, dependencies, and tests

Depends first on a pure overview model and native nonactivating panel; thumbnails additionally need
ScreenCaptureKit, a bounded cache, cancellation, and separate permission policy. Injected tests cover
permission denied/granted/revoked, no-prompt metadata mode, parked/ignored/minimized/full-screen
windows, stale drag/drop, display changes, bounded images, cleanup, and zero capture/persistence/log
side effects. Live tests must separately verify system permission copy and capture behavior.

### Product decisions still required

1. Is metadata-only useful enough for a first increment?
2. Are actual thumbnails worth a second privacy permission and restart-sensitive first-run flow?
3. What is shown for parked/minimized/full-screen/ignored windows?
4. May last-visible thumbnails be cached, for how long, and only in memory?
5. Is the overview global, per interaction display, or one panel per display?
6. Does click switch only, and does drag send-only by default with a modifier for follow?

## 4. Layout presets and current direct manipulation

### Current boundary

These are separate capabilities and must not be treated as one future feature:

1. **Layout presets — research only:** named reusable geometry/topology templates independent of
   live window IDs.
2. **Manual split resizing — implemented:** resizing a focused Tiled window adjusts the nearest
   compatible divider, clamps it to safe minimum geometry, and reflows the affected tree.
3. **Title-bar drag-to-swap — implemented:** a position-only drag holds the focused tile in place
   while the pointer is down, then swaps leaves with the tile under the pointer on release.
4. **Radial edge/corner placement — implemented:** preview and commit share the same session-local
   tree proposal and revalidate the captured window/workspace/display context before applying it.

The three implemented behaviors have deterministic tree and engine coverage. Their feel and
Accessibility behavior with real third-party windows remain part of the signed-app validation
boundary; test evidence alone does not close that work. Presets remain the only feature proposal in
this section. The existing radial Tiled Place contract supplies an important invariant for any
future editor: preview makes zero AX writes; commit validates the same captured context and applies
one normal layout transaction.

### Model and persistence implications

A preset can store a versioned normalized split topology, orientation/ratios, gaps/padding, minimum
participant rules, and a deterministic policy for too few/many windows. It cannot store live window
identities. It remains undecided whether presets are global, profile-owned, or copied into a
workspace on selection. Migrating an existing flat Tiled workspace must preserve its current visual
arrangement until a preset or direct action is deliberately applied.

Current direct manipulation changes the WindowServer-session layout tree/order/weights. Durable
cross-session tree persistence would require stable semantic slots rather than window IDs and
remains a later preset decision.

### Interaction and platform feasibility

Current manual split resizing and drag-to-swap reconcile Accessibility frame observations from the
focused Tiled window; they do not expose app-owned divider handles or an overview/editor. The radial
placement preview is a nonactivating WindowRanger overlay. A future preset editor could add explicit
handles, ghost frames, or native in-app drag/drop, but that UI is neither implemented nor approved.

Every gesture should capture window/workspace/display/topology generation, keep focus on the exact
target, perform no AX writes during hover/preview, validate again on release, commit once, and
register one Undo when the prior session topology is still valid. Cancel, Escape, competing user
focus, display change, sleep, and profile/workspace change discard the preview.

### Failure, dependencies, and tests

The implemented manipulation paths depend on the pure Tiled tree, transaction/diff layout
application, focus verification, nonactivating placement preview, and bounded Undo. Existing tests
cover divider selection/clamping, drag target selection, swap/insertion topology, contextual
exclusions, preview zero-write, single commit, and stale-context cancellation. Presets still need
separate participant-count, aspect-ratio, persistence, migration, and editor tests after their
product boundary is decided.

### Product decisions still required

1. Are presets global, profile-owned, or embedded per workspace?
2. Which initial presets are worth naming, and how do they handle extra/fewer windows?
3. Does Freeform gain snap presets, or are presets Tiled-only initially?
4. Which topology, participant policy, or semantic slot state can persist without guessing window
   identity?

## Recommended research order

1. Prototype a pure metadata overview model and a pure layout-preset resolver in tests/offscreen UI.
2. Resolve pinned-mode ownership and all-pinned semantics before changing the display-mode enum.
3. Define arrangement capture/apply data and privacy boundaries before any “Save Desk” UI.
4. If thumbnails remain desirable, perform an isolated ScreenCaptureKit permission/parked-window
   feasibility spike with no integration into normal startup.
5. Consider an explicit overlay editor only if the current native resize, drag-to-swap, and radial
   placement interactions prove insufficient in live validation.
