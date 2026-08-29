# Future workspace systems — decision brief

Status: **Research only for pinned-display mode, the optional overview, Tiled templates, and profile
activation restoration.** Named arrangements were resolved against because Profiles already own
that product boundary. Section 4 distinguishes unapproved template/editor ideas from the Tiled
placement and direct-manipulation behavior that is already implemented and tested.

This brief scopes adjacent concepts without turning them into one feature. It preserves the
current product boundaries: profiles are reusable configuration rather than window snapshots;
Unified and Independent Displays remain the only built display modes; and layouts remain Freeform,
Tiled, and Accordion.

The related [Omarchy-inspired research](omarchy-inspired-ideas.md) is reconciled through the same
canonical queue rather than forming a second roadmap. Profiles own reusable environments; Tiled
templates own topology only; profile activation may later reconcile or launch configured apps.
Searchable commands and the Quick App Shelf have their own queue entries.

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
informational chips switch workspaces. Workspace switch/move, profile transitions, Command Palette
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

### Resolved boundary — 25 August 2026

Do not add a separate named-arrangement object or Settings destination. A Writing, Coding, Customer
Call, or Presentation environment is already a Profile: it owns named workspaces, Application Rules,
workspace layouts, abstract display roles, and explicit or automatic activation. Capturing the same
assignments and layouts in a second object would create competing ownership, persistence, sync,
preview, and activation paths.

The useful parts now have narrower homes:

- copying ordinary layout settings between workspaces is a direct Workspace Settings action;
- optional recovery and launch of profile-configured apps belongs to profile activation;
- reusable 2x2 or asymmetric geometry belongs to Tiled topology templates;
- a future temporary group must prove a genuinely session-only interaction before receiving its own
  model.

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

### Selected first implementation

WR-100 resolves the preview portion of this decision. One reusable metadata canvas is used by
Workspace Settings tabs and the Full menu-bar workspace hover panel. ScreenCaptureKit enrichment is
off by default, separately permissioned, one-shot, bounded, and memory-only. Denied, revoked,
protected, minimized, parked, or otherwise unavailable captures keep their metadata/icon
placeholder; preview construction never changes a live window to obtain pixels. Settings tab clicks
remain edit-only. In the menu-bar surface, background clicks switch workspace and item clicks focus
the exact represented window when it remains valid, falling back within the represented application
if the window vanished during the interaction. Drag-and-drop window movement remains a later
interaction decision rather than being inferred by this preview foundation.

## 4. Tiled templates and current direct manipulation

### Current boundary

These are separate capabilities and must not be treated as one future feature:

1. **Tiled templates — research only:** reusable normalized geometry/topology independent of live
   window IDs, such as four equal slots in a 2x2 grid or one large slot on the left with two stacked
   on the right.
2. **Manual split resizing — implemented:** resizing a focused Tiled window adjusts the nearest
   compatible divider, clamps it to safe minimum geometry, and reflows the affected tree.
3. **Title-bar drag-to-swap — implemented:** a position-only drag holds the focused tile in place
   while the pointer is down, then swaps leaves with the tile under the pointer on release.
4. **Radial edge/corner placement — implemented:** preview and commit share the same session-local
   tree proposal and revalidate the captured window/workspace/display context before applying it.

The three implemented behaviors have deterministic tree and engine coverage. Their feel and
Accessibility behavior with real third-party windows remain part of the signed-app validation
boundary; test evidence alone does not close that work. Templates remain the only feature proposal in
this section. The existing radial Tiled Place contract supplies an important invariant for any
future editor: preview makes zero AX writes; commit validates the same captured context and applies
one normal layout transaction.

### Model and persistence implications

A template can store a versioned normalized split topology, semantic slots, ratios, gaps/padding,
and a required participant count. It cannot store applications or live window identities. The
recommended first boundary is Tiled-only, a small built-in set, and an exact-count requirement: the
action is unavailable with a clear explanation when the workspace does not contain the right number
of eligible windows. Current windows fill slots deterministically in layout order. A custom builder
should embed its resulting topology in the workspace rather than create another named library;
selecting a built-in likewise copies its topology into the workspace. Migrating an existing flat
Tiled workspace must preserve its current visual arrangement until a template or direct action is
deliberately applied.

Profiles already provide broader Writing and Coding personalities. Grid, Columns, 2x2, and
master/detail arrangements are candidate Tiled templates; behavior such as Presentation or
Transient needs a separately justified lifecycle policy, not a parallel workspace-mode enum.

Current direct manipulation changes the WindowServer-session layout tree/order/weights. Durable
cross-session tree persistence would require stable semantic slots rather than window IDs and
remains a later template decision.

### Interaction and platform feasibility

Current manual split resizing and drag-to-swap reconcile Accessibility frame observations from the
focused Tiled window; they do not expose app-owned divider handles or an overview/editor. The radial
placement preview is a nonactivating WindowRanger overlay. A future template builder could add explicit
handles, ghost frames, or native in-app drag/drop, but that UI is neither implemented nor approved.

Every gesture should capture window/workspace/display/topology generation, keep focus on the exact
target, perform no AX writes during hover/preview, validate again on release, commit once, and
register one Undo when the prior session topology is still valid. Cancel, Escape, competing user
focus, display change, sleep, and profile/workspace change discard the preview.

### Failure, dependencies, and tests

The implemented manipulation paths depend on the pure Tiled tree, transaction/diff layout
application, focus verification, nonactivating placement preview, and bounded Undo. Existing tests
cover divider selection/clamping, drag target selection, swap/insertion topology, contextual
exclusions, preview zero-write, single commit, and stale-context cancellation. Templates still need
separate participant-count, aspect-ratio, persistence, migration, and editor tests after their
product boundary is decided.

### Product decisions still required

1. Should participation continue to count every eligible window, or deliberately use at most one
   window from each application?
2. Which initial built-ins are worth naming beyond 2x2 and large-left/two-right?
3. Should an exact-count template adapt after a window opens or closes, or fall back to ordinary
   Tiled behavior until its count matches again?
4. How does a user inspect and change deterministic slot order without binding apps to templates?
5. Which topology, participant policy, or semantic slot state can persist without guessing window
   identity?

## 5. Profile activation restoration and launch

Profiles can become more complete environments without introducing arrangements. Two independent,
per-profile options are worth refining:

1. **Restore configured apps:** when the user explicitly applies a profile, reconcile running apps
   covered by enabled Application Rules with explicit workspace assignments. Move their eligible
   windows through the normal admission/rule path. Do not reveal every profile workspace at once;
   only the workspace or workspaces made active by the profile appear on screen.
2. **Launch missing configured apps:** after explicit manual profile activation, open configured
   applications that are not running. Newly discovered windows enter through the same normal
   admission/rule path, without focusing each app as it launches.

Both options should default off. Quick Apps remain Shelf-owned and are not launch targets. The first
increment should not launch apps for automatic display, dock, topology, or Game Mode profile
switches; those can happen without the user intending to start a work session. Protected full-screen
sessions and the existing ignored/deferred/floating safety rules remain authoritative.

### Product decisions still required

1. Does restore unhide or deminimize eligible windows, or only correct workspace/display placement?
2. How should launch order, duplicate instances, failure, timeout, and partial completion be shown?
3. What happens when another profile is applied while launches or delayed window discovery are in
   progress?
4. Should automatic activation ever gain a separate launch permission after manual behavior is
   proven?
5. What is the Undo boundary when app launch itself cannot be safely reversed?

## Recommended research order

1. Resolve manual profile-activation restoration and launch semantics before changing activation.
2. Prototype a pure Tiled-template resolver and accessible offscreen builder in tests/offscreen UI.
3. Resolve pinned-mode ownership and all-pinned semantics before changing the display-mode enum.
4. If thumbnails remain desirable, perform an isolated ScreenCaptureKit permission/parked-window
   feasibility spike with no integration into normal startup.
5. Consider an explicit overlay editor only if the current native resize, drag-to-swap, and radial
   placement interactions prove insufficient in live validation.
