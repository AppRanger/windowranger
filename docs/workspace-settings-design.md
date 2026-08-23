# Workspace Settings Master-List and Inspector

## Status

Implementation contract for the selected native macOS Settings redesign. The selected visual
reference is:

`<local-artifact>`

The reference is design evidence only. WindowRanger uses native SwiftUI/AppKit controls, materials,
typography, and SF Symbols; the bitmap is not shipped.

## Goals

- Keep the existing searchable Settings sidebar as the stable first navigation level.
- Make Workspaces the single destination for reusable workspace configuration.
- Use a native center master list and extensible right inspector that can grow without adding more
  top-level Settings destinations.
- Keep selection, ordering, profile changes, iCloud refreshes, and validation deterministic.
- Preserve all current profile, display-role, layout, shortcut, and recovery semantics.

## Information architecture

The Settings window has three visible regions while Workspaces is selected:

1. **Settings sidebar:** General, Sync, Behavior, Profiles, Profile Switching, Menu Bar, Focus Border,
   Displays, Workspaces, Applications, Quick App Shelf, Shortcuts, Command Palette, and Debug-only
   Diagnostics. Appearance and Layouts are retained only as legacy destination aliases and resolve
   to their current owners.
2. **Editing-profile context:** a full-row icon-and-name selector sits in the sidebar above the four
   profile-owned destinations. Selecting a profile changes the Settings edit target without affecting
   the desktop; Profile Status owns name/icon editing and the separate **Use Profile** action that
   activates and pins it on this Mac until automatic selection resumes.
3. **Workspace master column:** ordered workspace list, Add/Duplicate/Delete controls, and Restore
   WindowRanger Defaults. The selected profile's Unified/Independent mode lives in Displays.
4. **Workspace inspector:** editable identity, home display role, workspace key and derived shortcut
   summaries, layout-specific controls, reusable-setting reset, and active-workspace window repair.

General owns permissions and startup. Sync owns iCloud scope and status. Profiles owns the reusable
library and explicit activation, while Profile Switching owns this Mac's automatic selection rules.
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
| Workspace names, keys, ordering, add/remove, built-in reset | Master list and selected-workspace identity |
| Unified / Independent Displays | Displays page control |
| Workspace display role | Inspector General section |
| Freeform / Tiled / Accordion | Inspector Layout section |
| Automatic / Horizontal / Vertical orientation | Tiled and Accordion inspector state |
| Inner gaps and outer screen padding | Tiled-only inspector controls |
| Accordion visible-edge padding | Accordion-only inspector control |
| Reset current workspace windows | Inspector Repair section, retaining the existing active-workspace safety command |
| Workspace shortcut summaries | Inspector General section |

The derived shortcuts remain exactly those registered by `HotKeyManager`: Control-Option plus the
workspace key switches to a workspace; Command-Option plus the key sends the focused window there.
This milestone does not invent independently recordable per-workspace chords.

## Master-list behavior

- Rows use the workspace UUID as stable selection identity. Reordering never changes selection.
- A row shows a native layout symbol, name, abstract home-display role, layout summary, and truthful
  derived keycap.
- Drag reorder and accessible/context-menu Move Up/Move Down call the same store operation.
- Add creates a unique name and usable one-character key. Duplicate clones only the selected
  workspace's reusable layout configuration and display role, then resolves name/key uniqueness.
- Delete is disabled for the only remaining workspace and selects the nearest surviving row.
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
- Switch to and Move Window to are read-only derived keycaps, not independent shortcut recorders.

### Layout

- **Freeform:** no geometry controls. Copy explains that frames remain manual while workspace
  visibility, focus, persistence, display assignment, quit/wake recovery, and safety repair remain
  managed.
- **Tiled:** orientation, inner horizontal/vertical gaps, and four outer screen paddings.
- **Accordion:** orientation and visible-edge padding only.
- Pre-upgrade workspaces with nil layout configuration retain their existing appearance until the
  user explicitly adopts current built-in geometry, preserving the existing migration boundary.

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
- Settings category, independently selected profile edit target, and currently inspected workspace
  are local UI state. They do not enter profile or iCloud data.
- Pause is runtime-only, starts off on every launch, and enters neither local persistence nor iCloud.

No profile/storage format migration is needed for this redesign. Existing profile-backed values stay
authoritative. The Settings-navigation migration keeps Displays as a current destination and maps
only saved or deep-linked Layouts destinations to Workspaces.

## Search and deep links

Search routes workspace names/keys, home display, layout type, orientation, gaps, padding, and
workspace reset to Workspaces. Display mode, role definitions, and physical bindings route to
Displays; profile name/icon and activation route to Profiles; profile display-role menu-bar icons
route to Menu Bar; and automatic selection routes to Profile Switching. A dynamic workspace-name
result selects that exact UUID. Global commands route to Shortcuts. Release search never
exposes Debug-only Diagnostics.

## Extension points and intentional omissions

The inspector is section-based so future real workspace behavior can be added without changing the
master-list structure. This pass intentionally omits:

- illustrative window-behavior toggles that the current product does not implement;
- arbitrary workspace colours/icons without an established persisted model;
- separate per-workspace shortcut objects;
- physical monitor fingerprint editing outside Displays;
- live open-window identities or transient AX/CG state in profile definitions.

## Accessibility and sizing

- Rows and controls have complete VoiceOver labels/hints; full workspace/display names remain
  available when visual text truncates.
- Drag reorder has Move Up/Move Down alternatives.
- Native Forms, Lists, segmented pickers, keyboard traversal, Dynamic Type, light/dark appearance,
  Increased Contrast, and Reduced Motion are used rather than custom imitations.
- The Settings window receives a larger sensible minimum/default size for the three-column design,
  while remaining resizable and preserving the existing single-window coordinator.

## Visual QA and acceptance

An opt-in, genuinely non-hosted fixture renders the production Settings view at 1440 x 1024 with
Independent Displays, Writing selected, Studio Display, and Accordion. It must not construct
`AppDelegate`, start the engine, prompt Accessibility, register hotkeys, contact iCloud, mutate login
items, or show a live window.

The final reference/prototype comparison must check column proportions, hierarchy, padding,
typography, native borders/materials, selected-row state, clipping, large-text resilience, and the
absence of invented controls. P0/P1/P2 differences are fixed before `design-qa.md` records
`final result: passed`.

Acceptance requires deterministic tests for navigation migration, search routing, selection and
reorder, CRUD uniqueness, display-role/layout editing, layout-specific visibility, profile/iCloud
boundaries, reset/Undo, reset wording, and the offscreen render seam, followed by the normal isolated
suite and signed Debug/Release milestone builds.
