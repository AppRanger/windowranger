# Menu Bar Presentation Design QA

## Scope

This QA covers only WindowRanger's native status component. Wallpaper, neighbouring macOS status
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
register global shortcuts, launch `WindowRanger.app`, or touch live windows.

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

# Command Wheel Option 1 Icon Refinement QA

## Evidence

- **Source visual truth:**
  `/Users/chris/.codex/generated_images/019ff4d3-2ed6-7c61-bb88-5f1e3ded820b/exec-16077120-e8e8-4f1d-9273-6e9032bf36fa.png`
  (1,254 x 1,254 pixels, generated visual direction).
- **Rendered implementation:**
  `.build/radial-menu-icon-option-1-fidelity/windowranger-radial-base.png`
  (1,240 x 1,240 pixels for the 620 x 620-point production `RadialMenuView` at 2x).
- **Combined comparison input:**
  `.build/radial-menu-icon-option-1-fidelity/option-1-six-icon-focused.png`
  (1,440 x 960 pixels). Each of the six 124-pixel source regions is paired directly with its
  production counterpart and enlarged by the same factor; no density-only differences were
  treated as findings.
- **State:** Both views show the complete top-level action ring over the same dark presentation
  context. The generated source highlights Place Window while retaining neutral centre copy, a
  state the production interaction model does not emit. Icon fidelity was therefore judged across
  the complete annulus rather than from the reference accent or centre content.
- **Focused region:** the combined input deliberately magnifies every action. This was added after
  the signed live wheel revealed one- or two-pixel alignment and scale differences that the earlier
  whole-wheel-only comparison missed.

## Findings and comparison history

- **P2 resolved — Move to Space was too dense and untidy at production size.** The revised
  composition restores the reference's two upper focus corners and central title-bar stroke, keeps
  the transfer arrow outside the window, and uses one explicit title-bar window instead of the
  three-dot browser treatment.
- **P2 resolved — Reset Windows in Space had the wrong geometry.** The installed candidate used an
  oversized arrowhead, a pinched loop, and an undersized browser-style window. The revised symbol
  uses a clockwise open loop, a centered explicit title-bar window, and regular optical weight.
- **P2 resolved — the remaining four actions drifted from the set.** Place and Go are enlarged to
  the reference's optical footprint, Go uses three independent workspace tiles rather than a
  colliding four-tile grid, and Previous/Next use longer regular-weight opposing arrows.
- **Final icon result:** Place Window is a framed single window; Go to Space is a workspace grid
  with a lower-right navigation target; Previous and Next are plain opposing arrows; Move and
  current-space Reset retain distinct transfer and restore silhouettes. Reset All, Layout Type,
  Profiles, disclosure chevrons, and generated child symbols remain intentionally unchanged.
- **Typography and copy:** unchanged; the production San Francisco hierarchy, centre text,
  truncation rules, and accessibility labels remain authoritative.
- **Spacing and layout rhythm:** unchanged. Every icon remains inside the existing fixed optical
  frame, with no wedge, ring, centre, disclosure, or hit-region movement.
- **Colours and tokens:** unchanged. The compositions inherit the existing monochrome foreground,
  accent selection, contrast, and material tokens.
- **Image quality and asset fidelity:** the implementation uses sharp native SF Symbols at every
  render scale rather than shipping the generated bitmap. The generated glow is presentation
  context, not part of the selected icon grammar.
- **Content and interaction:** commands, labels, selection behavior, keyboard paths, pointer paths,
  and accessibility semantics are unchanged. The same composite renderer is used in the wheel,
  centre, Settings catalogue, and Settings production preview.

## Verification

- Focused production-wheel and Settings snapshot suites: 2 tests passed during final rendering.
- Complete non-hosted local checkpoint: 535 tests passed.
- Offscreen production evidence: nine wheel states rendered successfully for the fidelity revision.
- Unsigned Debug application: universal arm64/x86_64 build passed.
- Signed-app visual validation: pending explicit installation approval.

No actionable P0/P1/P2 mismatch remains in the scoped icon pass. Live scale, animation, and varied
desktop backgrounds remain the signed-app validation boundary.

final result: passed

---

# Workspace Settings Design QA

## Scope and reference

This QA covers the native Workspaces Settings destination selected from:

`<local-artifact>`

The reference supplies the master-list-plus-inspector hierarchy. WindowRanger uses the real
profile-backed workspace/display/layout models, native SwiftUI/AppKit controls and SF Symbols; the
bitmap and its illustrative unsupported Window behavior toggles are not included in the product.
The complete information and persistence contract is in `docs/workspace-settings-design.md`.

## Offscreen production render

`WorkspaceSettingsVisualSnapshotTests` hosts the production `SettingsView` in a non-ordered,
borderless AppKit window for one bounded SwiftUI update cycle. That realizes native
`NavigationSplitView` and `List` descendants without starting `AppDelegate`, the workspace engine,
Accessibility, global hotkeys, iCloud, login-item services, or the normal app. The fixture renders
at 1440 x 1024 points and 2x Retina scale.

- Final production preview: `<local-artifact>`
- Same-canvas selected-reference comparison: `.build/settings-redesign-previews/window-manager-settings-comparison.png`
- Accessibility text-size render: `.build/settings-redesign-previews/window-manager-settings-workspaces-accessibility-text.png`

The representative state is Independent Displays, **Writing** selected, **Studio Display** as its
abstract Home Display role, and **Accordion** with 16-point visible-edge padding.

## Iteration history

1. **Information architecture (P0):** the previous Workspaces, Displays, Layouts, and
   workspace-shortcut controls were scattered across four destinations. Workspaces now owns one
   reorderable master list and one selected-workspace inspector; physical role bindings remain in
   Profiles and global commands remain in Shortcuts.
2. **Offscreen-layout correction (fixture P0):** a detached hosting view did not realize virtualized
   AppKit lists, while the first full-window capture did not allow SwiftUI's update cycle to settle.
   The final fixture uses a non-ordered borderless window, a bounded main-run-loop update, and the
   AppKit-supported view cache path. Selected table rows are marked emphasized only in the fixture
   so the reference comparison represents an active Settings window without activating or showing
   the test process.
3. **Proportion and polish pass (P1/P2):** the first complete render made the Settings sidebar too
   narrow and the workspace master too wide. Final column targets are a 260-point sidebar, a
   roughly 385–420-point master, and a flexible inspector. The workspace key editor now suppresses
   its redundant field label, every row exposes full VoiceOver ownership, and long explanatory copy
   wraps without clipping.

## Final fidelity review

- **Hierarchy:** the far-left searchable Settings sidebar remains stable; page-level display mode,
  workspace rows and CRUD occupy the centre; identity, General, layout-specific controls and Repair
  occupy the inspector. Selection remains UUID-based across reorder/profile refresh.
- **Controls:** native Lists, Forms, segmented Pickers, TextFields, Steppers, buttons, context menus,
  drag-and-drop and Undo are used. Freeform hides automatic geometry; Tiled shows orientation,
  inner gaps and outer padding; Accordion shows orientation and visible-edge padding.
- **Typography and spacing:** system type, materials and grouped-form spacing preserve authentic
  macOS density. The production render is intentionally a little denser than the generated image's
  enlarged presentation typography.
- **Colour and assets:** semantic materials/control accent and real SF Symbols support light/dark,
  Increased Contrast and inactive-window states. No bitmap, handcrafted SVG, copied product icon,
  or fake behavior control is shipped.
- **Accessibility:** rows expose complete names, Home Display ownership, layout and key even when
  visual text truncates. Drag reorder has context-menu and named VoiceOver Move Up/Down actions; an
  accessibility text-size render exercises the full hierarchy through native layout and rasterization.
- **Intentional differences (P3):** the generated reference contains an ellipsis menu, custom
  per-workspace colours/icons, and three Window behavior toggles that the product does not support.
  They are omitted rather than presented as dead or misleading controls. Offscreen segmented
  controls retain AppKit's inactive-window shading; the live focused Settings window uses the
  user's normal control accent.

No scoped P0, P1, or P2 mismatch remains.

final result: passed

---

# Contextual Radial Menu Design QA

## Scope

This QA covers the production two-ring radial component, not the reference wallpaper, pointer,
sample app window, or image-generation scale. WindowRanger renders the result with SwiftUI/AppKit,
native materials, and SF Symbols; the reference bitmap is not included in the app.

The current icon pass translates the user-selected **Action-First Gestures** exploration into native
SF Symbols. The generated image is visual direction rather than a bitmap asset or a demand to copy
its presentation-only glow and custom line art.

## Reference mapping

- Selected target: `<local-artifact>`
- Selected icon direction:
  `/Users/chris/.codex/generated_images/019ff4d3-2ed6-7c61-bb88-5f1e3ded820b/exec-5ac0b909-e704-4a3b-a283-5535be24d90a.png`
- Stable centre: cancel zone plus current selection/preview.
- Inner ring: equal full-circle top-level wedges with a clear selected state and disclosure marks.
- Outer ring: generated children around the same centre, with quieter unselected treatment and a
  strong selected wedge.
- Tiled Place: eight compass-positioned actions and a pure miniature proposed-layout preview.

## Offscreen production renders

`Tests/RadialMenuVisualSnapshotTests.swift` renders the real production `RadialMenuView` at Retina
scale from the genuinely non-hosted test bundle. It does not construct `AppDelegate`, request
Accessibility, install hotkeys/event taps, contact iCloud, start login services, or launch
`WindowRanger.app`.

- Neutral, Place, Move to Space, Go to Space, Layout Type, and Profiles states are generated by
  `scripts/render-radial-menu-previews.sh`.
- The selected reference was centre-cropped to a 620 x 620 square and placed beside the 620 x 620
  production Place Window state at
  `.build/radial-menu-icon-option-3/option-3-place-comparison.png`; this keeps the same open group,
  compass ring, selected corner and viewport scale in one comparison input.

## Comparison findings

- **Hierarchy and scale:** the screenshot-backed WR-028 pass replaces the earlier compact geometry
  with a 420-point outer disc, 264-point inner ring, and approximately 110-point centre. This gives
  selected labels, state, and previews enough room without ellipses while retaining clear hierarchy.
- **Geometry:** every resolved inner item and every dynamic child gets an equal full-circle wedge;
  eight Place actions retain compass order. Move/Profile renders demonstrate clean redistribution
  at different child counts with no dead slots.
- **Selection:** the control-accent inner/outer wedges are immediately legible. Unselected regions,
  thin separators, and monochrome symbols stay restrained rather than becoming nine heavy buttons.
- **Centre:** the centre remains fixed as groups open. Neutral state shows workspace/layout/display
  context without a persistent Cancel instruction; selection shows its real symbol, complete label,
  and optional state detail; Place keeps the exact miniature of the pure proposed Tiled layout or
  the focused Freeform window's usable-screen target.
- **Symbols and labels:** both rings use fixed optical icon centres. Generated children are icon-only,
  with complete text retained in the selected centre and accessibility label. Workspace and profile
  workspace destinations use configured key symbols and profiles use stable numbered symbols
  instead of blank or repeated glyphs. Layouts keep their
  semantic symbol and add a separate current badge. Group chevrons rotate with their wedge and point
  radially toward the outer ring rather than uniformly to the right.
- **Action-first icon grammar:** Place Window uses framed half/corner occupancy symbols in exact
  compass order. Move, Go, Profiles, Layout, Previous/Next, current-workspace reset, and global reset
  now have distinct silhouettes. Directional square arrows reserve traversal for Previous/Next;
  circular arrows remain reset/reflow actions. The production result deliberately uses real SF
  Symbols rather than copying the exploration's custom strokes.
- **Current layout correction:** live review of the first pass found that Layout Type still showed a
  generic split-pane glyph. The inner item now inherits Freeform, Tiled, or Accordion from the active
  workspace. The supplied 80 x 66 Accordion crop was compared beside the production outer-ring
  symbol at `.build/radial-menu-layout-current-icons/accordion-icon-comparison.png`; production keeps
  the rounded three-pane silhouette and enlarges the central pane as requested. A dedicated
  `windowranger-radial-accordion-layout.png` state verifies both the inner current-layout symbol and
  selected outer action.
- **Material and accessibility:** one native glass vocabulary supports dark/light appearance,
  Increased Contrast strengthens borders, Reduced Motion removes bloom/scale animation, and full
  VoiceOver labels/hints accompany the icon-only outer ring. Centre activation remains an accessible
  cancel action. Seven offscreen states include a deliberately oversized-label stress case.
- **Interaction evidence:** pure state coverage proves that an open group stays latched while the
  pointer crosses the centre and another inner wedge, reaching the outer ring invalidates the
  crossed-wedge timer, and a deliberate longer dwell still changes groups.
- **Remaining boundary:** offscreen production states have no unresolved visual P0/P1/P2 mismatch.
  Pointer feel, long real names, panel edge clamping, and both activation styles still require the
  signed Debug app and physical input.

The focused production/icon suite passes 116 tests, local quick verification passes all 527
non-hosted tests, and the unsigned universal arm64/x86_64 Debug target builds successfully.

automated result: passed; icon fidelity result: passed; signed-app interaction result: pending

## Command Wheel Settings preview comparison

- **Source visual truth:** `.build/radial-menu-layout-current-icons/windowranger-radial-move-to-space.png`
  (1240 x 1240 pixels, production wheel at 2x).
- **Implementation:** `.build/radial-menu-settings-preview/windowranger-settings-command-wheel-preview.png`
  (840 x 760 pixels for a 420 x 380 point Settings fixture at 2x).
- **Combined evidence:** `.build/radial-menu-settings-preview/qa/production-settings-comparison.png`
  (1680 x 760 pixels). The source was normalized to compact Settings scale and placed beside the
  implementation in the same dark appearance and open Move to Space state.
- **Full-view and focused-region result:** A separate crop was unnecessary because the implementation
  embeds `RadialMenuView`; the combined view clearly resolves symbols, separators, centre copy, and
  disclosure chevrons. Geometry, typography, opacity tokens, material, icon assets, selection color,
  and centre content match production. Different workspace keys and child counts are fixture data.
- **Add state:** Catalogue order is preserved and the available list becomes empty only when every
  known family is saved; the native Add menu disables from that same result.
- **Findings:** No actionable P0/P1/P2 mismatch. The preview is intentionally noninteractive because
  the editable catalogue controls live below it; accessibility exposes one descriptive label.
- **Comparison history:** The earlier Settings-only circles and capsules were a P1 fidelity drift.
  Replacing them with the production renderer resolves it in the combined post-fix evidence above.

final result: passed

---

# Command Palette Placement Halo Design QA

## Scope and references

- Selected option 1 reference:
  `/Users/chris/.codex/generated_images/01a01e25-3f66-7ef1-b715-6d393aedeeaf/exec-924321bf-99cc-43ef-a917-baf9cea7ec7a.png`
- Offscreen production render:
  `.build/command-palette-placement-halo/windowranger-command-palette-placement-halo.png`
- Same-state, same-viewport side-by-side comparison input:
  `.build/command-palette-placement-halo/option-1-reference-production-comparison.png`
- The production fixture uses the real `CommandPaletteView`, contextual Freeform placement
  provider, native material, SF Symbols, stable eight-position compass order, and a selected Right
  Half state at Retina scale.

## Comparison findings

- **Interaction model:** the original icon-only control becomes the centre of the halo. Expanding
  it preserves the palette, search query, results, selection, and key focus; Escape collapses the
  halo before dismissing the palette.
- **Scope:** the halo contains only truthful Freeform or Tiled positions. Layout choice, Accordion
  resize, floating, workspace, profile, and application commands remain in search. The Globe/Fn
  wheel resolves the identical position provider as one direct ring.
- **Hierarchy and geometry:** the 140-point segmented ring keeps eight Loop-style directions in
  their expected compass positions. It overlaps the palette edge deliberately, while transparent
  panel overflow prevents clipping and keeps the 620 x 480 palette surface stationary.
- **Feedback:** hover uses the normal accent, the complete placement name appears just to the right
  of the ring, and the centre returns to the same placement symbol so collapse is discoverable.
- **Native adaptation:** production uses system materials, controls, typography, and SF Symbols
  rather than copying the mock's custom line art, wallpaper, or presentation-only glow. Light,
  dark, Increased Contrast, Reduced Motion, help, and accessibility labels remain supported.
- **Intentional difference (P3):** the reference shows a shorter curated result list and a blue
  focus ring. The production snapshot uses its full truthful contextual results and an inactive
  offscreen search field; the signed key panel supplies the native focus treatment at runtime.
- **Remaining boundary:** the offscreen render has no unresolved P0/P1/P2 visual mismatch. Pointer
  feel, key-focus retention, panel shadow, real-screen edge behavior, and committed window movement
  still require the signed installed app.

## Installed follow-up correction

- The first signed live render exposed an AppKit shadow artefact that offscreen SwiftUI rendering
  could not show: the enlarged transparent panel received a black outline around the halo. The
  panel now disables its window-level shadow only while expanded; the halo keeps its own bounded
  material shadow.
- The unavailable position control is now omitted instead of disabled.
- Keyboard interaction now has an explicit submode: Right Arrow enters from an empty search, arrows
  traverse generated placements, Return commits, and Escape collapses the halo and restores search.
- These corrections are implemented and automated; the updated signed live render remains pending.

visual result: passed; signed-app interaction result: pending
