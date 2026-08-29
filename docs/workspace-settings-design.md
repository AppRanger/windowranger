# Workspace Settings Visual Tabs and Inspector

## Status

Implementation contract for the selected native macOS Settings redesign. The selected visual
reference is:

`<local-artifact>`

The selected direction is option 2: a horizontal strip of large workspace tabs with truthful layout
miniatures, followed by a compact Details panel beside a wider Layout and Repair inspector. The
reference is design evidence only. WindowRanger uses native SwiftUI/AppKit controls, materials,
typography, and SF Symbols; the bitmap is not shipped.

## Goals

- Keep the existing searchable Settings sidebar as the stable first navigation level.
- Make Workspaces the single destination for reusable workspace configuration.
- Make layout and workspace identity scannable through a native visual tab strip that can reuse the
  active profile's read-only managed-window preview while retaining saved-layout miniatures for
  inactive profiles and unavailable runtime state.
- Use a compact identity/actions panel and extensible Layout and Repair inspector that can grow
  without adding more top-level Settings destinations.
- Keep selection, ordering, profile changes, iCloud refreshes, and validation deterministic.
- Preserve all current profile, display-role, layout, shortcut, and recovery semantics.

## Information architecture

The Settings window has these visible regions while Workspaces is selected:

1. **Settings sidebar:** General, Sync, Behavior, Profiles, Menu Bar, Focus Border,
   Displays, Workspaces, Applications, Quick App Shelf, Shortcuts, Command Palette, and Debug-only
   Diagnostics. Appearance, Profile Switching, and Layouts are retained only as legacy destination
   aliases and resolve to their current owners.
2. **Editing-profile context:** a full-row icon-and-name selector sits in the sidebar above the four
   profile-owned destinations. Selecting a profile changes the Settings edit target without affecting
   the desktop; Profile Status owns name/icon editing and the separate **Use Profile** action that
   activates and pins it on this Mac until automatic selection resumes.
3. **Workspace tab strip:** horizontally scrollable ordered workspace tabs, each showing its name,
   key, and either the active profile's managed-window preview or a saved Freeform, Tiled, or
   Accordion fallback, followed by Add Workspace. The selected profile's Unified/Independent mode
   lives in Displays.
4. **Workspace details:** compact editable identity, home display role, workspace key and derived
   shortcut summaries, reorder/duplicate/delete controls, and collection reset.
5. **Layout and Repair inspector:** wider layout-specific controls, reusable-setting reset, and
   active-workspace window repair.

General owns permissions and startup. Sync owns iCloud scope and status. Profiles owns the reusable
library, explicit activation, and this Mac's profile-centric automatic selection assignments.
Displays owns the selected profile's display mode and role names plus this Mac's physical bindings.
Menu Bar owns global
presentation plus the editing profile's display-role icon choices. Focus Border owns local border
presentation and application-specific radius overrides. Behavior owns recovery, focus-following moves, trackpad
workspace switching, and application-unhide compatibility.
Shortcuts remains separate for global, non-workspace commands. Applications, Quick App Shelf, and
Command Palette retain their existing destinations.

## Existing-control mapping

| Existing location | New Workspaces location |
| --- | --- |
| Workspace names, keys, ordering, add/remove, built-in reset | Visual tab strip and Workspace details |
| Unified / Independent Displays | Displays page control |
| Workspace display role | Workspace details |
| Freeform / Tiled / Accordion | Layout panel |
| Automatic / Horizontal / Vertical orientation | Tiled and Accordion Layout state |
| Inner gaps and outer screen padding | Tiled-only Layout controls |
| Accordion visible-edge padding | Accordion-only Layout control |
| Copy another workspace's layout | Layout action; copies style and geometry only |
| Reset current workspace windows | Repair panel, retaining the existing active-workspace safety command |
| Workspace shortcut summaries | Workspace details |

The derived shortcuts remain exactly those registered by `HotKeyManager`: Control-Option plus the
workspace key switches to a workspace; Command-Option plus the key sends the focused window there.
This milestone does not invent independently recordable per-workspace chords.

## Visual-tab behavior

- Tabs use the workspace UUID as stable selection identity. Reordering never changes selection, and
  selecting a distant/deep-linked workspace scrolls its tab into view.
- A tab shows the workspace name and truthful derived keycap. Active-profile tabs may consume a
  read-only descriptor built from the engine's already tracked window identities and intended
  geometry. If there is no runtime descriptor, the selected profile is inactive, or capture is
  unavailable, a native abstract miniature continues to communicate Freeform, Tiled, or Accordion.
  Selecting any Settings tab changes only the edit target and never activates a workspace.
- The optional Screen Recording setting progressively enriches the selected workspace with bounded
  in-memory thumbnails; all active-profile tabs receive cheap metadata previews. Metadata/icon
  placeholders remain the baseline and no Settings render requests permission or changes a live
  window. While this pane is visible, the engine's existing broad refresh emits a semantic
  invalidation only when tracked identities or intended geometry actually change; it adds no timer.
- Drag reorder and accessible/context-menu Move Left/Move Right call the same store operation. The
  trailing Add Workspace tab is also the drop target for moving a workspace to the end.
- Add creates a unique name and usable one-character key. Duplicate clones only the selected
  workspace's reusable layout configuration and display role, then resolves name/key uniqueness.
- Delete is disabled for the only remaining workspace and selects the nearest surviving tab.
- Restore WindowRanger Defaults retains the established product wording and uses deterministic
  built-in IDs so surviving references are not needlessly rewritten.

## Inspector behavior

### Identity

The header uses a native layout symbol and editable workspace name. WindowRanger does not currently
persist arbitrary workspace colours or icons, so the reference's illustrative custom icon picker is
intentionally omitted.

### General

- Home Display edits the profile's synced abstract display-role assignment. Physical monitor binding
  remains local and is edited in Displays.
- Workspace Key accepts one supported character and warns clearly about duplicates or unsupported
  values.
- Generated shortcuts are shown as compact, plain read-only text beneath the editable Workspace Key,
  not as independent shortcut recorders. Changing the workspace key updates both generated commands;
  their modifier keys remain owned by the global Shortcuts destination.

### Layout

- **Freeform:** no geometry controls. Copy explains that frames remain manual while workspace
  visibility, focus, persistence, display assignment, quit/wake recovery, and safety repair remain
  managed.
- **Tiled:** orientation plus two lightweight visual geometry rows. A four-tile diagram maps inner
  horizontal/vertical gaps to exact native controls, and an inset-screen diagram maps Top, Right,
  Bottom, and Left outer padding to their physical edges. The compact diagrams use a compressed
  visual scale so small non-zero values remain visible; this affects only the preview, while the
  displayed point values and applied window geometry remain exact. Optional Keep equal controls
  normalize and link only the active edit group; they are transient inspector state rather than
  profile data. Link activation leaves untouched legacy geometry nil, while linked multi-value
  writes participate in native Undo.
- **Accordion:** orientation and visible-edge padding only.
- Pre-upgrade workspaces with nil layout configuration retain their existing appearance until the
  user explicitly adopts current built-in geometry, preserving the existing migration boundary.
- **Copy Layout** chooses another workspace in the same edited profile and copies only its layout
  style and reusable geometry. Destination identity, role assignment, app rules, and live membership
  remain unchanged. The copy participates in native Undo and creates no named preset library.

### Repair and reset

- **Reset This Workspace** resets the selected workspace's layout to Freeform and its geometry to
  WindowRanger's built-in values. It deliberately preserves name, key, home display role, app rules,
  and live window membership. The reusable-setting change participates in native Undo.
- **Bring Active Workspace Windows Back On Screen** retains the existing safety command: recover
  managed windows in the interaction display's active workspace, clear transient positioning state,
  and reapply that workspace's current layout. It does not change reusable settings and cannot be
  meaningfully undone after Accessibility frame writes.

## Persistence boundaries

- Synced profile content: profile name/icon, workspace definitions/order, key, layout/geometry,
  display mode, abstract display roles and menu-bar icons, workspace-to-role assignments, app rules, and the ordered Quick
  App Shelf plus its shared presentation.
- Synced global content: Menu Bar presentation/labels/highlight, global shortcuts and Command
  Palette activation, focus-following moves, and automatic application-unhide behavior.
- Local per Mac: active profile/manual pin, automatic trigger mappings including the foreground
  foreground full-screen `LSSupportsGameMode` profile target, physical monitor
  fingerprints and role bindings, current focus, active runtime workspace state, selected Quick App,
  open-window membership, trackpad preferences, Focus Border preferences and application overrides,
  permissions, login-item state, and diagnostics.
- Settings category, independently selected profile edit target, currently inspected workspace, and
  temporary Tiled geometry-link controls are local UI state. They do not enter profile or iCloud
  data. Geometry links reset when the inspected workspace changes and do not themselves cross the
  explicit legacy-geometry adoption boundary.
- Pause is runtime-only, starts off on every launch, and enters neither local persistence nor iCloud.

No profile/storage format migration is needed for this redesign. Existing profile-backed values stay
authoritative. The Settings-navigation migration keeps Displays as a current destination and maps
only saved or deep-linked Layouts destinations to Workspaces.

## Search and deep links

Search routes workspace names/keys, home display, layout type, orientation, gaps, padding, and
workspace reset to Workspaces. Display mode, role definitions, and physical bindings route to
Displays; profile name/icon, activation, and automatic selection route to Profiles; profile
display-role menu-bar icons route to Menu Bar. A dynamic workspace-name
result selects that exact UUID. Global commands route to Shortcuts. Release search never
exposes Debug-only Diagnostics.

## Extension points and intentional omissions

The details and inspector panels are section-based so future real workspace behavior can be added
without changing the visual-tab structure. This pass intentionally omits:

- illustrative window-behavior toggles that the current product does not implement;
- arbitrary workspace colours/icons without an established persisted model;
- separate per-workspace shortcut objects;
- physical monitor fingerprint editing outside Displays;
- live open-window identities or transient AX/CG state in profile definitions.

## Accessibility and sizing

- Tabs and controls have complete VoiceOver labels/hints; full workspace/display names remain
  available when visual text truncates.
- Drag reorder has Move earlier/Move later alternatives.
- Native Forms, Lists, segmented pickers, keyboard traversal, Dynamic Type, light/dark appearance,
  Increased Contrast, and Reduced Motion are used rather than custom imitations.
- At wide widths Workspace details sits beside the wider Layout/Repair column. At compact widths the
  same panels stack beneath the still-horizontal, scrollable tab strip; no second list/detail screen
  or hidden action is introduced.
- The Settings window remains resizable and preserves the existing single-window coordinator.

## Visual QA and acceptance

An opt-in, genuinely non-hosted fixture renders the production Settings view at 1440 x 1024 with
Independent Displays, Writing selected, Studio Display, and Accordion. It must not construct
`AppDelegate`, start the engine, prompt Accessibility, register hotkeys, contact iCloud, mutate login
items, or show a live window.

`scripts/render-settings-preview.sh` selects the focused Workspaces scope by default and emits wide
and minimum-width Light/Dark states plus wide and minimum-width Dark states with nine workspaces, a
selected long name, and horizontal overflow. No extra environment switch is required to reproduce
that evidence.

The final reference/prototype comparison must check tab proportions and layout miniatures, panel
hierarchy, padding, typography, native borders/materials, selected state, horizontal overflow,
compact stacking, clipping, large-text resilience, and the absence of invented controls. P0/P1/P2
differences are fixed before `design-qa.md` records
`final result: passed`.

Acceptance requires deterministic tests for navigation migration, search routing, selection and
reorder, CRUD uniqueness, display-role/layout editing, layout-specific visibility, profile/iCloud
boundaries, reset/Undo, reset wording, and the offscreen render seam, followed by the normal isolated
suite and signed Debug/Release milestone builds.
