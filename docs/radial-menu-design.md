# Contextual Radial Menu

**Status:** The renderer, captured-context validation, placement previews, and Globe/Fn input path
remain implemented. WR-060 supersedes the broad configurable Command Wheel with a searchable
Command Palette and uses this renderer only as a position-focused Placement Wheel. The hybrid is
implemented, automated-test verified, and accepted in the signed installed app.

## Current product scope

- The Placement Wheel resolves only truthful `Place Window` actions: Freeform halves and quarters
  or Tiled compass placements. It has one level with no family-selection ring.
- The Command Palette owns layout and Accordion resize commands alongside workspace, profile,
  recovery, focus, move, Quick App, and application commands.
- The palette's icon-only control expands those positions as a Placement Halo without dismissing
  the key palette. The optional Globe/Fn hold opens the same actions directly in the nonactivating
  Placement Wheel at the pointer.
- Saved broad-wheel definitions and activation styles remain decodable for migration safety but are
  no longer authoritative or editable in Settings.

The remaining sections document the reusable renderer/provider and historical migration contract.
Where they describe the nine-family production wheel or its editor, treat that as the preserved
pre-WR-060 design rather than current user-facing behavior.

## Goals

- Make the command wheel a reusable two-level system driven by a versioned top-level definition and one immutable runtime context.
- Give every visible top-level item an equal wedge so the resolved inner ring always fills 360 degrees without dead slots.
- Let a top-level item be direct-only, submenu-only, or expose both an optional primary action and generated children.
- Generate children from the current workspaces, profiles, layout, focused window, and display state instead of storing child lists.
- Preserve exact target validation, nonactivation, focus safety, interaction-display placement, Press to Toggle, Hold to Show, keyboard access, native Undo, iCloud sync, and privacy-safe diagnostics.
- Optionally admit a deliberate Globe/Fn hold through the same captured-context Hold-to-Show path while forwarding a quick tap and every chord unchanged to macOS.
- Make future command types additive: a provider/catalogue entry supplies metadata and contextual actions; the renderer, geometry, editor, and persistence schema remain generic.

## Non-goals

- No third ring, recursive menus, arbitrary commands, scripts, plug-ins, shell execution, mouse/trackpad trigger marketplace, or theme marketplace.
- Profiles do not own wheel definitions, the wheel shortcut, or activation style.
- The wheel does not snapshot windows or bypass existing command validation, app-rule precedence, workspace routing, or layout transactions.
- Preview never writes Accessibility frames and never promises a result that the normal layout commit cannot produce.

## Selected visual reference

The selected target is:

`<local-artifact>`

Only the radial component is a target. The implementation uses native AppKit/SwiftUI materials and real SF Symbols; the backdrop and sample window are presentation context and the bitmap is not shipped.

Reference mapping:

- A stable, generous centre is the neutral zone and describes the current selection. Escape and
  centre activation retain cancellation behavior without a persistent cancel label.
- The inner ring is the persistent top-level catalogue, with equal translucent wedges and a clear selected wedge.
- A group discloses a complete outer ring around the same centre. The outer hierarchy is visually quieter than the selected inner wedge.
- Icons remain compact and monochrome. Both rings use fixed optical icon centres; generated outer
  actions are icon-only while hover, keyboard selection, accessibility, and help expose their full
  label. The action-first grammar uses a framed-window transfer symbol for Move to Space, a framed
  window target for Place, a workspace-grid navigation target for Go to Space, plain directional
  arrows for Previous/Next,
  layered workspace/profile symbols, scoped restore symbols, and a split-pane layout symbol.
  Placement children show the occupied half or corner inside one window frame instead of generic
  direction arrows. Workspace and profile destinations use stable ordinals rather than repeated
  placeholders.
  The current top-level compositions are a provisional visual checkpoint. WR-049 tracks a complete
  catalogue review that prefers unchanged native SF Symbols where suitable and reserves custom
  symbols for actions without a clear native match; this does not change command semantics.
- A disclosure chevron distinguishes groups from direct-only commands without creating a separate
  hit target. It follows the wedge angle and points radially toward the generated outer ring.
- Reduced Motion removes bloom/scale movement; increased contrast strengthens separators and selection outlines.

## Terminology

- **Definition:** the synced, versioned ordered list of top-level item type IDs.
- **Catalogue:** static metadata for every known top-level type: stable ID, label, SF Symbol, summary, and provider.
- **Provider:** pure contextual logic that resolves one optional primary action and zero or more child actions.
- **Captured context:** one immutable focused-window/workspace/display/profile snapshot plus a validation token.
- **Resolved item:** renderer-ready metadata with an optional primary action and generated children.
- **Inner ring:** equal wedges for every resolved top-level item.
- **Outer ring:** children of one active inner item, normally equal 360-degree wedges.
- **Primary action:** an optional command committed directly from the inner wedge.
- **Secondary action:** an explicitly advertised alternate commit, such as Option to Move & Follow.

## Configuration and provider model

`RadialMenuDefinition` is Codable and stores only:

- a schema version; and
- an ordered, unique list of stable `RadialTopLevelItemID` values.

It never stores child commands, labels, SF Symbols, profile IDs, workspace IDs, display IDs, or window IDs. Unknown IDs survive decoding long enough to report that repair is needed, but are omitted from resolution.

`RadialTopLevelCatalogue` owns the available item types and supplies a provider for each one. The Settings editor and resolver read the same catalogue. Adding a future type requires a new stable ID, metadata, and provider; it must not require renderer, geometry, editor, or persistence branching.

Each provider receives the captured context and returns:

- optional primary `RadialResolvedAction`;
- ordered child actions;
- optional semantic child geometry (`equalCircle` or `compass`);
- current-state text; and
- an omission reason for diagnostics when neither primary nor children are valid.

If a provider has a valid primary action but no children, it remains as a direct-only wedge. If it has children but no primary, it is submenu-only. If it has neither, it is omitted and the remaining wedges close the angular gap.

## Resolved runtime model

The renderer consumes only `RadialMenuModel`:

- captured validation token and display/workspace summary;
- ordered resolved top-level items;
- safe label and SF Symbol metadata;
- optional primary action and optional alternate action;
- generated child actions and child geometry policy;
- current/selected state markers; and
- accessibility labels and hints.

An action contains an opaque shared `WindowManagerCommand`, safe diagnostic ID, label, symbol, optional alternate command/label, current-state marker, and optional preview descriptor. The renderer emits semantic selections; it does not know workspace, profile, layout, or window business rules.

## Geometry rules

- For `N > 0` resolved inner items, wedge `i` occupies exactly `2π/N`, centred at `-π/2 + i × 2π/N`. Small visual separator strokes may inset each rendered path, but semantic hit regions remain contiguous across the full circle.
- Dynamic workspace, profile, and layout children use the same equal full-circle rule for their visible count.
- Tiled placement uses eight semantic compass angles: Top, Top Right, Right, Bottom Right, Bottom, Bottom Left, Left, Top Left. If a choice is intentionally omitted because it is geometrically indistinguishable, the remaining choices retain their compass angles; this is the one documented case where semantic positions may leave gaps.
- Centre, inner, transition, and outer radii are shared pure tokens. Ring hysteresis prevents small movement around a boundary from repeatedly changing rings.
- Angular hysteresis keeps the prior wedge until the pointer crosses a bounded margin into its neighbour.
- A group may open only after the pointer dwells on its inner wedge for the configured short disclosure interval, except Hold to Show may open immediately once the pointer deliberately crosses outward from that group.
- Once open, a group stays latched while the pointer crosses the centre or another inner wedge on
  the way to any outer child. Reaching the outer ring cancels a crossed-wedge switch. Another inner
  item replaces the group only after a deliberate longer dwell, so travel does not masquerade as a
  navigation decision.
- The centre stays fixed when the outer ring appears. The complete two-ring panel is clamped to the interaction display's visible frame.
- Practical item counts retain a minimum icon arc. If a future catalogue exceeds the tested legible maximum, resolution omits lowest-priority contextual items with a diagnostic rather than rendering unreadable wedges.

## Interaction state machine

Common states are `idle`, `inner(item?)`, `groupPending(item, generation)`, `groupOpen(item, child?)`, `committing`, and `cancelled`.

Opening uses pointer intent before menu context is captured. WindowServer front-to-back order
selects only the actual frontmost eligible tracked window beneath the pointer; the engine requests
exact focus and captures the runtime context after the bounded focus observation. Desktop,
WindowRanger/transient surfaces, untracked or ineligible windows, and failed exact focus preserve
the established focused-window fallback rather than targeting through another surface. The exact
application activation requested by this pointer-focus transaction does not cancel its own pending
Globe/Fn or shortcut gesture; a different process, expired deadline, or superseded focus generation
still cancels normally.

Common cancellation events are Escape, centre selection, outside click, short hold tap, trigger cancellation, lost captured target, display/workspace/profile change, sleep/wake, app deactivation, and a superseding activation generation.

### Press to Toggle

1. The shortcut captures and validates context, then shows the nonactivating panel.
2. Hover selects an inner wedge. Dwelling on a group opens its generated outer ring.
3. Clicking an inner direct-only item commits its primary action.
4. Clicking an inner item with both a primary action and children commits the primary action; hover/dwell remains the route into its children.
5. Clicking a submenu-only inner item opens/keeps its submenu and never fires an accidental command.
6. Clicking an outer wedge commits that child.
7. Moving inward clears only the outer selection. The open group remains available across the
   centre; dwelling deliberately on another inner item switches or closes the group.
8. Keyboard traversal cycles inner items, enters a group, cycles children, returns inward, activates a valid action, or cancels with Escape.

### Hold to Show

1. A tap shorter than the global threshold does nothing.
2. Crossing the threshold captures and validates context, then shows the same resolved model.
3. Moving within the inner ring selects an item. Moving deliberately outward from a group opens/selects its children.
4. Release over a direct-only inner item commits its primary action.
5. Release over an inner item with primary plus children commits its primary action.
6. Release over a submenu-only inner item cancels; merely highlighting a category never runs a command.
7. Release over an outer child commits that child.
8. Centre, no selection, Escape, stale generation, or invalid context cancels.

### Optional Globe/Fn hold

The hardware gesture is an additional device-local trigger; it does not replace the saved global
shortcut or change that shortcut's Press-to-Toggle/Hold-to-Show setting. When enabled, a passive
Quartz session event tap observes `maskSecondaryFn`, keyboard, mouse-button, and system-defined
events without participating in their delivery. A separate active tap receives only key down/up on
a dedicated user-interactive run loop. Neither requests permission, and they are installed only
when the app already has its normal Accessibility trust.

- Fn alone starts a candidate. Crossing the shared hold delay opens the existing Hold-to-Show
  session exactly once; Fn release uses the normal release-commit/no-selection-cancel path.
- Releasing before the delay leaves every event untouched, so macOS remains responsible for the
  configured Globe quick-tap action. WindowRanger never invokes or replays the emoji picker.
- Any key, function/media event, mouse button, or other modifier before or during the candidate
  cancels it. The entire Fn chord remains untouched.
- The active callback fast-passes every ordinary key without consulting MainActor state. Only the
  native Globe action event associated with an accepted long hold is filtered, preventing the same
  release from also invoking the Mac's quick-tap action.
- Event-tap failure and timeout fail open. A timeout stops the monitor instead of automatically
  re-enabling an unresponsive filter; toggling the setting is the explicit retry boundary.
- A foreground application declared as a game through public bundle metadata suspends both optional
  Globe/Fn and workspace-swipe monitors, including for borderless windows. This is intentionally
  separate from native-fullscreen geometry protection, and the ordinary saved wheel shortcut remains
  available.
- Escape, the ordinary wheel shortcut, app/session/lifecycle changes, monitor interruption, and
  configuration changes supersede the gesture. Once accepted, a deliberate hold has no fixed
  duration and remains active until Fn release or one of those explicit cancellation signals.
- Public event data does not provide a dependable built-in-versus-external keyboard identity, so
  compatible external Fn/Globe keys intentionally use the same conservative admission rules.

This is based on Loop's public event-tap implementation pinned at
[`2467291f3095a571e80fdb0024845d4dedf111c9`](https://github.com/MrKai77/Loop/tree/2467291f3095a571e80fdb0024845d4dedf111c9),
and Apple's public [`CGEventFlags`](https://developer.apple.com/documentation/coregraphics/cgeventflags),
[`CGEvent.tapCreate`](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)),
[`CGEvent.tapEnable`](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:)),
and [`AXIsProcessTrusted`](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted)
interfaces. Loop is evidence for the native special-event/pass-through split, not code or behavior
imported wholesale.

### Direct plus submenu precedence

Hover/dwell or outward motion is disclosure. Click/release on the inner wedge is the optional primary action. The outer wedge is always the selected child. A submenu-only item cannot commit from the inner ring. Once disclosed, the group remains latched through pointer travel; a longer dwell is required to adopt another inner item. The centre label/hint says either “Release to …”, “Click to …”, or “Move outward for …” so the precedence is not hidden.

## Dynamic filtering

- Ignored popups never enter captured context or become action targets.
- A missing manageable focused window leaves workspace/profile actions only.
- Keep-on-all windows omit Move to Space.
- App-rule-excluded windows omit contradictory layout/floating/placement controls.
- Floating and automatically floating windows remain focusable but never enter placement geometry unless an existing explicit “Return to Layout” action is valid.
- Minimized, full-screen, deferred, parked, non-focusable, stale, and other-display windows never become placement targets.
- Independent Displays scopes workspaces and commands to the interaction logical/physical display. Unified retains actual display affinity and never falls back to main merely because focus is temporarily unavailable.
- Empty groups are omitted and remaining wedges are recalculated; no saved slot reserves dead geometry.

## Initial top-level catalogue

The built-in order is the following nine types.

### 1. Move to Space

- Submenu-only when a focused movable managed window exists.
- Children are valid destination workspaces in stable user order, excluding the window's current workspace and any destination blocked by app-rule or Independent Displays routing.
- Primary child command preserves the existing send-only default.
- Holding Option while committing a child uses the child's advertised alternate “Move & Follow” command. This is a secondary affordance, not a third level or new global shortcut.
- Keep-on-all and ignored windows omit this item.

### 2. Resize / Place

- Tiled, participating window: submenu-only and labelled **Place Window**. Children follow the eight compass placement contract in [Radial Tiled Placement](radial-tiled-placement.md). Hover previews the exact proposed tree frames; preview performs zero AX writes and commit adopts one validated tree through one normal layout transaction.
- Tiled, explicitly/automatically floating window: a valid existing “Return to Layout” action may appear as a direct-only primary action; no placement preview is generated before return.
- Accordion, participating window: submenu-only **Resize** with truthful Smaller and Larger padding actions where bounded change is possible.
- Freeform, eligible focused window: submenu-only **Place Window** with the same eight compass positions.
  Edge choices are usable-display halves and corner choices are quarters. Hover previews the exact
  focused-window frame with zero Accessibility writes; commit validates the captured frame/display,
  changes no other window or layout state, and supports exact-frame Undo/Redo.
- App-rule excluded, ignored, minimized, full-screen, deferred, stale, or ineligible windows are omitted and never pulled into layout.

The tiled tree, preview, migration, persistence, and atomic commit semantics are subordinate to and defined by [Radial Tiled Placement](radial-tiled-placement.md). This document does not duplicate or weaken that contract.

### 3. Go to Space

- Submenu-only.
- Children are valid workspaces in stable user order and correct display scope.
- Each child uses the workspace's configured alphanumeric key as its badge; unsupported multi-key
  bindings use the generic workspace symbol rather than inventing a list number.
- The active workspace is omitted from commands and shown as current state in the centre/accessibility description, avoiding a dead no-op child.

### 4. Next Space

- Direct-only using the existing cycle-workspace command.

### 5. Previous Space

- Direct-only using the existing reverse cycle-workspace command.

### 6. Profiles

- Submenu-only when at least one meaningful selection is available.
- Children are reusable profiles in stable saved order, excluding the currently active profile as a no-op.
- If automatic selection is manually pinned, append **Resume Automatic**.
- Profile selection uses the existing safe transition and never snapshots window identities.

### 7. Reset Windows in Space

- Direct-only, scoped to the captured current workspace and interaction display through the existing reset command.

### 8. Reset All Windows

- Direct-only and labelled/accessibly described as affecting every managed window.
- Uses the existing broad “Bring All Managed Windows Back On Screen” recovery path.
- In Hold-to-Show, highlighting the item and releasing the trigger dismisses without running it.
  The centre and accessibility hint require an explicit click or Return. Press-to-Toggle retains
  ordinary direct-command activation.

### 9. Layout Type

- Primary action cycles the current workspace layout using existing command semantics.
- Outer children represent Freeform, Tiled, and Accordion. The current child keeps its normal layout
  name, adds a separate current badge, and explains in centre detail that selecting it reapplies the
  layout; other children select their layout.
- Layout changes never silently move a floating, excluded, ignored, minimized, full-screen, or ineligible window into geometry.

## Workspace, profile, and display semantics

- Workspace order comes from the active profile definition, never UUID or discovery order.
- Profile order comes from the synced profile library. Active/manual/automatic state is local and merely annotates or filters resolved actions.
- Profile selection commands route through SettingsStore's safe transition coordinator rather than mutating profile state in the renderer.
- Independent Displays uses the captured interaction display, workspace homes, and connected fallback already resolved by the engine; selecting an item never rewrites a missing display home.
- Unified uses one workspace state but preserves each window's actual display affinity.
- All actions carry one correlation ID and the captured validation token; the newest activation supersedes stale sessions.

## Tiled tree and preview boundary

The current flat weighted Tiled layout is converted lazily to a local per-workspace/per-display tree that reproduces the current rectangles. The tree is session state, not profile content or iCloud content. It is trusted only inside the current WindowServer session.

Preview asks the engine for a pure `TiledPlacementProposal` containing the old/proposed tree fingerprints and exact frames calculated with real usable bounds, gaps, outer padding, ratios, and current participants. The preview renderer draws those rectangles inside the wheel panel and never receives AX elements. Commit revalidates the token, target identity, participant set, topology, and proposal, then stores the proposed tree and invokes one normal layout batch. Failure retains the old tree.

## Settings editor and migration

The preserved pre-WR-060 Command Wheel Settings design was ordered as:

1. enabled state, global shortcut, activation style, optional device-local Globe/Fn hold, and hold delay;
2. a compact rendering of the production wheel with representative contextual children, plus
   interaction help;
3. ordered top-level catalogue editor; and
4. Repair and Reset to Defaults.

The editor can add a missing known top-level type, remove/hide a type, and drag/reorder selected
types. Add is disabled once every known family is already present. It does not rename catalogue
labels/icons or edit child lists. Mutations use native Undo. The preview uses the production wheel
renderer and saved family order, so its geometry, materials, symbols, centre, and disclosure
direction cannot drift into a Settings-only design. Search indexes the nine types, generated-child
concepts, shortcut, activation, Repair, and Reset.

One private-install migration recognizes the previous version-1 direct/group definition:

- the exact old built-in definition becomes the complete new built-in order;
- known direct or group command references map to the corresponding new top-level types in first-occurrence order;
- workspace previous/next/reset map to their explicit types; move-window groups map to Move to Space; resize maps to Resize/Place; layout maps to Layout Type;
- unknown entries and manual child-only constructs are omitted and set a repair notice;
- if conversion yields no valid type, use the minimal safe default and keep Reset available.

The new definition is the sole authoritative saved format after a successful write. It remains a global setting and follows the existing iCloud preference boundary; profile changes never replace it.

## Accessibility, motion, and contrast

- Every inner and outer action exposes full label, group ownership, current state, alternate Option action where applicable, ring/depth, and an actionable VoiceOver hint.
- Centre exposes the selected action and cancellation semantics without becoming a normal app-window focus target.
- Keyboard order follows saved inner order and generated child order.
- Reduced Motion removes scale/bloom and uses immediate opacity/state changes.
- Increased Contrast strengthens separators, outlines, and selected state without relying on colour alone.
- Long workspace/profile names are visually bounded on the outer ring while accessibility/help
  exposes the full text. Numeric workspace symbols do not repeat the same number as a second label.

## Focus and nonactivation

- The panel is borderless, nonactivating, cannot become main, does not appear in normal window cycling, and never enters WorkspaceEngine discovery/persistence.
- Presentation uses ordering that does not activate WindowRanger or replace the focused app/window. Input is observed through an injected controller/event source; tests never install a live event tap.
- Opening, hovering, previewing, and cancelling perform no AX writes and do not alter interaction display.
- Commit is the only mutation boundary and routes through the shared command dispatcher.

## Diagnostics and privacy

Debug diagnostics record correlation/session ID, definition version, context-filtered top-level IDs, selected top-level/action IDs, ring/depth, activation mode, safe Globe/Fn state/reason, workspace/display short IDs, group disclosure source, alternate-action modifier, preview/proposal fingerprint, validation result, and dismissal reason.

Diagnostics never include window titles, document names, URLs, typed content, full paths, screen contents, profile names, or workspace names. Repeated unchanged hover/preview events are deduplicated.

## Persistence and profile boundary

- Wheel definition, enabled state, shortcut, activation style, and hold delay are global preferences and may sync through the existing iCloud key-value path.
- The Globe/Fn opt-in is global rather than profile-owned, but intentionally local to each Mac because it describes that Mac's hardware and Globe configuration. It defaults off and is excluded from profile definitions and iCloud payloads.
- Profile definitions, selected profile, physical display bindings, and window session state remain separate according to their existing local/synced boundaries.
- Tiled trees and exact window keys are local WindowServer-session state only and never sync.

## Failure and stale-context behaviour

- Unknown catalogue IDs are omitted and make Repair visible; malformed/empty definitions resolve to a minimal safe fallback.
- A removed workspace/profile between preview and commit invalidates the action.
- A changed focused window, workspace, display topology, active profile, layout participant set, or WindowServer session invalidates preview/commit.
- Duplicate notifications and rapid trigger presses are generation-tokened and idempotent; latest activation wins.
- A failed tree validation or AX layout transaction keeps the prior tree and emits bounded feedback/diagnostics.
- Sleep, wake, display disconnect, quit, and app deactivation cancel the panel and preview without orphan UI.

## Test matrix

- Codable versioning, one-off migration, unknown-ID repair, default/reset, iCloud/global-not-profile persistence.
- Catalogue add/remove/reorder, stable IDs, native Undo plan, no manual child persistence.
- Inner equal 360-degree geometry for 1, 2, 3, 9, and practical larger counts; dynamic outer full-circle geometry; semantic compass positions; dead zone; angular/ring hysteresis; full-panel clamping.
- Contextual omission and gap closure for no window, keep-on-all, app-rule exclusion, floating/automatic dialog, ignored, minimized/full-screen/deferred, Unified, and Independent Displays.
- Direct-only, submenu-only, and primary-plus-submenu click/release precedence; initial and
  group-switch dwell; outward disclosure; latched travel through the centre and other inner wedges;
  inward return; keyboard traversal; Escape/centre/outside cancellation.
- Press and Hold threshold, short tap, valid release, no-selection release, Option alternate, stale generation, rapid re-entry, and reentrancy.
- Globe/Fn default-off/local persistence, unchanged quick tap, exact/below/above threshold, one open per hold, indefinite accepted hold, release commit, no-selection and Escape cancellation, every chord class/modifier ordering, duplicate flags, passive ordinary-input observation, synthetic-Globe-only active filtering, timeout fail-open/manual retry, borderless declared-game suspension, lifecycle/configuration cancellation, ordinary-shortcut supersession, and reuse of the nonactivating interaction-display context.
- Stable workspace/profile ordering, active/current state, Resume Automatic, send-only and Move & Follow, profile transition routing.
- Freeform eight-way fixed-frame proposals, Accordion resize, Tiled eight-way structural proposals,
  flat-to-tree conversion, edge/corner transformations, preview/commit frame identity, zero AX writes
  during preview, atomic commit, reset recovery, session invalidation, and display partition isolation.
- Accessibility labels/hints, Reduce Motion, increased contrast tokens, nonactivation/focus retention, and privacy-safe diagnostics.
- Offscreen production renders for neutral, Place, Move to Space, Go to Space, Layout Type, and
  Profiles states.

## Visual QA

- Render the production component offscreen at Retina scale without AppDelegate, Accessibility, global hotkeys, login items, or a normal app launch.
- Compare the selected reference and production render side by side at the same component scale/state.
- Verify centre stability, equal inner wedges, selected hierarchy, full outer ring, icons, separators, material, labels, display clamping, and high-contrast/Reduced-Motion variants.
- Record reference, snapshot paths, findings, iterations, and a truthful pass/block result in `design-qa.md` without replacing the existing menu-bar QA record.

## Acceptance criteria

- Configuration stores only ordered known top-level type IDs; providers generate all runtime children.
- Every visible inner item fills an equal share of 360 degrees and contextual omission leaves no gap.
- Dynamic child rings fill 360 degrees; Tiled placement preserves documented compass semantics.
- Direct-only, submenu-only, and direct-plus-submenu interactions are deterministic in Press and Hold modes.
- All nine initial types use existing shared commands or narrowly added shared commands, with correct workspace/profile/display scope.
- Tiled preview performs zero AX writes and matches the atomically committed layout.
- The panel does not activate WindowRanger, steal focus, or admit itself to managed-window state.
- Migration, Repair, Reset, Undo, Settings search, iCloud/global persistence, accessibility, diagnostics, and stale-context cancellation are verified.
- Offscreen visual comparison has no unresolved P0, P1, or P2 mismatch before handoff.

## Implemented delivery sequence

1. Replace the persisted manual child-list model with typed top-level IDs, catalogue/providers, migration, and pure resolution tests.
2. Replace geometry and interaction with equal wedges, two-ring state semantics, dwell/hysteresis, Option alternate, and focus-safe input/presentation.
3. Replace Settings with the top-level add/remove/reorder editor, Undo/Repair/Reset, search, and production preview.
4. Add the pure tiled-tree model, flat conversion, validation, edge/corner transformations, and persistence/session recovery.
5. Add preview proposals and atomic placement dispatch; integrate workspace/profile/reset commands.
6. Render and compare offscreen production states, update QA/README/roadmap, then run the full isolated test and signed build checkpoint.

The irreversible boundary remains the first Accessibility frame-write batch. Definition migration, context resolution, geometry, tree calculation, and preview are all side-effect-free before that point.
