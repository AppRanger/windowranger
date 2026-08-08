# Menu Bar Presentation Design QA

## Scope

This QA covers only WindowManager's native status component. Wallpaper, neighbouring macOS status
items, the clock, and the generated images' presentation scaling are context rather than app assets.
Production uses one persistent AppKit status item, a shared production content view, and real SF
Symbols; none of the reference bitmaps ship in the app.

## Reference mapping

| Mode | Selected reference | Production interpretation |
| --- | --- | --- |
| Compact | `<local-artifact>` | Overlapping-window app glyph, fine separator, and one minimal screen/workspace signal per connected display with an understated interaction dot. |
| Medium | `<local-artifact>` | Separate app glyph and equal-height neutral/accent display chips at native status-bar scale. |
| Full | `<local-artifact>` | A visibly distinct app-menu target followed by lightweight display groups, explicit workspace buttons, quiet secondary-active outlines, and a strong interaction-active fill. |

## Offscreen production renders

`Tests/MenuBarVisualSnapshotTests.swift` renders the same production content view used by the live
status item at Retina scale. The fixture does not construct `AppDelegate`, start Accessibility,
register global shortcuts, launch `WindowManager.app`, or touch live windows.

| Mode | Native canvas | Production render | Same-height reference comparison |
| --- | --- | --- | --- |
| Compact | 97 x 32 pt | `<local-artifact>` | `<local-artifact>` |
| Medium | 137 x 32 pt | `<local-artifact>` | `<local-artifact>` |
| Full | 246 x 32 pt | `<local-artifact>` | `<local-artifact>` |

The source artwork is 1942 x 809 px. Each comparison isolates its status component and normalises
both sides to 64 px high, avoiding a false match to the reference wallpaper or neighbouring system
icons.

## Iteration history

1. **Live-build finding (P0/P1):** Full used a second AppKit status item beside SwiftUI
   `MenuBarExtra`. macOS could reverse their order, synchronous presentation changes published back
   into an active SwiftUI update, and removing/recreating the Full item disconnected status scenes.
   The separate hit regions also left room for the historical workspace-P collision.
2. **Structural fix:** Compact, Medium, and Full now reconfigure one persistent AppKit status item on
   the next main-loop turn. Full places its app-menu target and workspace strip inside that same
   component. The root hit test admits only explicit workspace buttons; all other pixels route to
   the status item's menu.
3. **Visual pass (P2):** the first repaired render had signals that were too small/faint and used the
   wrong Full app glyph. The final token pass strengthened display ownership, placed Compact labels
   inside their screen symbols, used the grouped-grid Full glyph, and retained native menu-bar
   density.

## Final fidelity review

- **Typography:** native San Francisco text at 11-11.5 pt with compact semibold workspace labels;
  long names truncate in the component while tooltips and VoiceOver expose the complete value.
- **Spacing:** an 18 pt visual component height, compact radii, fine separators, and restrained gaps
  reproduce the reference hierarchy within a normal 32 pt status-bar canvas.
- **Colour/material:** semantic label colours and the user's control accent provide native
  light/dark/high-contrast behaviour; there are no copied gradients, shadows, or theme assets.
- **Assets:** `rectangle.on.rectangle`, `rectangle.split.2x2`, `laptopcomputer`, `display`, and
  `display.2` are real SF Symbols. No generated bitmap is embedded in the product.
- **State/ownership:** Independent mode shows each connected display's state; Unified mode shows one
  combined-display state. Compact uses a restrained interaction dot, Medium an accent chip, and Full
  an accent workspace control.
- **Interaction:** clicking the app glyph, a Compact signal, a Medium chip, a Full display symbol, or
  Full background opens the app menu. Only an explicit Full workspace button dispatches a workspace
  switch, and the button carries a typed workspace/display target rather than a reused status tag.
- **Remaining difference (P3):** the selected mockups use presentation-scale shadows and generous
  surrounding space. Production deliberately obeys the real macOS status-bar height and native
  material behaviour rather than reproducing those contextual effects.

No scoped P0, P1, or P2 mismatch remains.

final result: passed

---

# Contextual Radial Menu Design QA

## Scope

This QA covers the production two-ring radial component, not the reference wallpaper, pointer,
sample app window, or image-generation scale. WindowManager renders the result with SwiftUI/AppKit,
native materials, and SF Symbols; the reference bitmap is not included in the app.

## Reference mapping

- Selected target: `<local-artifact>`
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

- Place: `<local-artifact>`
- Move to Space: `<local-artifact>`
- Profiles: `<local-artifact>`
- Final same-canvas reference comparison: `<local-artifact>`

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
