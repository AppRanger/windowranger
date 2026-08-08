# Menu Bar Presentation Design QA

## Scope

This QA covers only WindowManager's native status components. Wallpaper, neighbouring macOS status items, clock content, and the generated images' presentation scaling are context rather than product assets. Production uses AppKit, SwiftUI, and real SF Symbols; none of the reference bitmaps ship in the app.

## Reference mapping

| Mode | Selected reference | Production interpretation |
| --- | --- | --- |
| Compact | `/Users/chris/.codex/generated_images/019fddc3-fa00-7de2-a467-ce7e3a81ba80/exec-7fb111da-4124-4c4c-abf1-7953993318dd.png` | Overlapping-window app glyph, fine separator, and one minimal screen/workspace signal per connected display with an understated interaction dot. |
| Medium | `/Users/chris/.codex/generated_images/019fddc3-fa00-7de2-a467-ce7e3a81ba80/exec-09568ad4-ea56-4145-a09d-8353103d561c.png` | Separate app glyph and equal-height neutral/accent display chips at native status-bar scale. |
| Full | `/Users/chris/.codex/generated_images/019fddc3-fa00-7de2-a467-ce7e3a81ba80/exec-5564e2b4-2327-4c72-b632-9425513eabf4.png` | Separate app/menu item plus lightweight display groups, explicit workspace buttons, quiet secondary-active outline, and strong interaction-active fill. |

## Offscreen production renders

The opt-in non-hosted fixture in `Tests/MenuBarVisualSnapshotTests.swift` rendered the real production SwiftUI primary view and AppKit Full strip at 2x scale. It does not construct `AppDelegate`, start Accessibility, register global shortcuts, launch `WindowManager.app`, or touch live windows.

- Compact: `/Users/chris/Documents/Codex/2026-08-07/realtime-voice-chat/outputs/window-manager-menu-bar-compact.png`
- Medium: `/Users/chris/Documents/Codex/2026-08-07/realtime-voice-chat/outputs/window-manager-menu-bar-medium.png`
- Full: `/Users/chris/Documents/Codex/2026-08-07/realtime-voice-chat/outputs/window-manager-menu-bar-full.png`

## Comparison findings

- **Spacing and scale:** 18-point production components, compact radii, fine separators, and restrained inter-group spacing match the reference hierarchy without imitating neighbouring system items.
- **Iconography:** `rectangle.on.rectangle`, `laptopcomputer`, `display`, and `display.2` provide native, semantically accurate symbols. Using a laptop symbol for the built-in panel is an intentional semantic improvement over repeating a generic monitor.
- **Active state:** Medium's interaction chip and Full's interaction workspace use a strong control-accent fill. A non-interaction display's active workspace uses a quiet accent outline. Compact uses a small dot below the signal rather than notification-badge styling.
- **Ownership:** Display ownership is legible through symbols and grouping. Independent mode renders every connected display; Unified renders one combined group.
- **Pressure and names:** long labels are bounded visually but complete in tooltips and VoiceOver. Deterministic compaction/overflow retains every connected display's active workspace.
- **Interaction safety:** the Compact and Medium surface is one menu-opening target. Full's app item remains separate; only explicit workspace buttons carry switch actions.
- **Iteration:** the first comparison exposed an inline Compact dot and a less reference-like app glyph. The final pass moved the dot beneath each signal and selected the native overlapping-rectangle symbol. No P0, P1, or P2 mismatch remains in the scoped component.

final result: passed

---

# Contextual Radial Menu Design QA

## Scope

This QA covers the production two-ring radial component, not the reference wallpaper, pointer,
sample app window, or image-generation scale. WindowManager renders the result with SwiftUI/AppKit,
native materials, and SF Symbols; the reference bitmap is not included in the app.

## Reference mapping

- Selected target: `/Users/chris/.codex/generated_images/019fddc3-fa00-7de2-a467-ce7e3a81ba80/exec-25a9791c-7f3d-4946-8979-a52eac917485.png`
- Stable centre: cancel zone plus current selection/preview.
- Inner ring: equal full-circle top-level wedges with a clear selected state and disclosure marks.
- Outer ring: generated children around the same centre, with quieter unselected treatment and a
  strong selected wedge.
- Tiled Place: eight compass-positioned actions and a pure miniature proposed-layout preview.

## Offscreen production renders

`Tests/RadialMenuVisualSnapshotTests.swift` renders the real production `RadialMenuView` at Retina
scale from the genuinely non-hosted test bundle. It does not construct `AppDelegate`, request
Accessibility, install hotkeys/event taps, contact iCloud, start login services, or launch
`WindowManager.app`.

- Place: `/Users/chris/Documents/Codex/2026-08-07/realtime-voice-chat/outputs/window-manager-radial-place.png`
- Move to Space: `/Users/chris/Documents/Codex/2026-08-07/realtime-voice-chat/outputs/window-manager-radial-move-to-space.png`
- Profiles: `/Users/chris/Documents/Codex/2026-08-07/realtime-voice-chat/outputs/window-manager-radial-profiles.png`
- Final same-canvas reference comparison: `/Users/chris/Developer/window-manager/.build/radial-comparison-final.png`

## Comparison findings

- **Hierarchy and scale:** the 330-point outer disc, 200-point inner ring, and generous centre match
  the reference's compact two-level hierarchy at native macOS scale.
- **Geometry:** every resolved inner item and every dynamic child gets an equal full-circle wedge;
  eight Place actions retain compass order. Move/Profile renders demonstrate clean redistribution
  at different child counts with no dead slots.
- **Selection:** the control-accent inner/outer wedges are immediately legible. Unselected regions,
  thin separators, and monochrome symbols stay restrained rather than becoming nine heavy buttons.
- **Centre:** the centre remains fixed as groups open. It shows the selected action, or for Place an
  exact miniature of the pure proposed layout, while remaining the cancel/dead zone.
- **Material and accessibility:** one native glass vocabulary supports dark/light appearance,
  Increased Contrast strengthens borders, Reduced Motion removes bloom/scale animation, and full
  labels/hints remain available to VoiceOver without permanently crowding the wheel.
- **Iteration:** the first render exposed an oversized hierarchy, saturated selection, duplicated
  outer labels, and a fixture-centering defect for asymmetric child counts. The final pass tightened
  the production radii/opacities, removed permanent child text, retained labels in the centre and
  accessibility, added thin wedge separation, and locked every offscreen fixture to the same centre.
  No scoped P0, P1, or P2 mismatch remains.

final result: passed
