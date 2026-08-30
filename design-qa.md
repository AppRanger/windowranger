# WR-066 Displays Presentation Design QA

## Scope and evidence

- **Selected visual source:**
  `/Users/chris/.codex/generated_images/01a046f9-13a7-7900-937a-afbfca1e14ed/exec-487064a8-408e-4e47-a907-eb508dde0a0e.png`
  (1,532 x 1,026 pixels). It establishes outcome-led workspace-switching choices and one combined
  role-to-monitor mapping surface.
- **Production renders:** `.build/displays-settings-previews/windowranger-settings-displays.png`
  and `windowranger-settings-displays-dark.png` render the real SwiftUI Settings view at 1,536 x
  1,024 points and Retina 2x. `windowranger-settings-displays-compact-dark.png` renders the same
  screen at the 760 x 560-point minimum window size.
- **State:** Dark and Light appearance, Desktop 2 screens profile, Switch separately selected,
  Primary Display mapped to DELL U4021QW, Side bar mapped to TYPE-C, and both bindings connected.
  The compact state stacks the two switching choices and retains the vertically scrollable native
  Form.
- **Normalization:** the final Dark render was downsampled to 1,532 x 1,026 pixels for comparison
  with the source. The source and implementation differ by only four pixels of nominal width and
  two pixels of nominal height before normalization.
- **Full comparison:** `.build/displays-settings-previews/displays-full-comparison.png` places the
  complete selected source and final native implementation together.
- **Focused comparisons:** `.build/displays-settings-previews/displays-switching-comparison.png`
  isolates the switching choices; `.build/displays-settings-previews/displays-roles-comparison.png`
  isolates the combined role mappings and sync/local boundary.

## Comparison history

1. **P2 resolved — the first visual cards read as decorated labels rather than primary choices.**
   The final cards use larger native display diagrams, a stronger selected outline and checkmark,
   and enough height to make the two outcomes immediately comparable.
2. **P2 resolved — the first deterministic fixture showed an unintended third role.** The fixture
   now reuses the profile's existing second role, leaving the approved Primary Display and Side bar
   pair and matching physical-monitor examples.
3. **P2 resolved — role rows were denser than the approved direction.** Additional vertical rhythm
   separates each reusable role while retaining standard native Form controls and separators.
4. **Adaptive result:** at the 760 x 560-point minimum size, the cards stack rather than compressing
   their diagrams or text. The same Form remains scrollable, so the role editor and add action are
   reachable without a separate compact interface.

## Fidelity surfaces

- **Information hierarchy:** Switch together and Switch separately lead with the real outcome;
  Unified and Independent remain quiet continuity terms. The selected profile's display setup
  follows as the second decision.
- **Role mapping:** every row keeps its profile-owned name, local physical-monitor picker, plain
  connection status, and delete action together. The footer states the reusable-versus-local
  persistence boundary once for the group.
- **Typography and spacing:** native San Francisco semantic text, grouped Form surfaces, 12-point
  card spacing, continuous corners, system separators, and expanded row padding preserve the
  existing Settings design system rather than copying bitmap effects.
- **Colour and assets:** semantic primary/secondary labels, the user's control accent, system green
  and orange status colours, and SF Symbols provide native Light, Dark, and increased-contrast
  behaviour. No generated bitmap or custom drawing asset ships in the app.
- **Interaction and accessibility:** each card is one button with selected state, outcome label,
  value, and hint. Diagrams are decorative and hidden from accessibility. Role name, local monitor,
  textual status, add, and delete remain native controls backed by the existing store operations.
- **Behavior boundary:** this is a presentation recomposition only. Display mode semantics, role
  UUIDs, profile/iCloud ownership, local `WorkspaceDisplayPin` persistence, ambiguous/disconnected
  handling, and the safe main-display fallback are unchanged.

No actionable P0, P1, or P2 visual mismatch remains. Pointer, keyboard, VoiceOver, and physical
monitor interaction remain the separately approved signed installed-app validation boundary.

final result: passed

---

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

---

# WR-066 Workspace Visual Tabs Design QA

## Scope and evidence

- **Source visual truth:**
  `/Users/chris/.codex/generated_images/01a046f9-13a7-7900-937a-afbfca1e14ed/exec-4754f52d-3200-4280-9912-4c1a828b8b4e.png`
  (1,487 x 1,058 pixels). The maintainer selected option 2: large layout-preview workspace tabs
  above a compact Details panel and wider Layout/Repair inspector.
- **Rendered implementation:**
  `.build/workspaces-design-qa/implementation/windowranger-settings-workspaces-dark.png`
  (2,880 x 2,048 pixels for a 1,440 x 1,024-point native macOS Settings viewport at 2x Retina
  density). Matching Light, Tiled-geometry Dark, 760 x 560-point minimum-width Light/Dark, and
  many-workspace/long-name renders live beside it in `.build/workspaces-design-qa/implementation/`.
- **State:** Dark appearance, Default profile, four workspaces with Writing selected and Accordion
  controls visible. The source labels the profile Travel and omits the fixture's truthful shortcut
  warning; those content-state differences are not layout mismatches. Additional renders select a
  final long-named Freeform workspace among nine workspaces at wide and compact widths.
- **Density normalization:** the source's 1,487 x 1,058 pixels and the implementation's 2,880 x
  2,048 Retina pixels were both normalized to 1,440 x 1,024 pixels before horizontal composition.
  Their aspect ratios differ by less than 0.1 percent, so no material crop or distortion was
  introduced.
- **Full-view comparison:**
  `.build/workspaces-design-qa/comparisons/windowranger-workspace-tabs-comparison-final.png`
  (2,880 x 1,024 pixels) places the selected source and final implementation together.
- **Focused comparison:**
  `.build/workspaces-design-qa/comparisons/windowranger-workspace-tabs-comparison-tabs-final.png`
  (2,880 x 500 pixels) isolates the tabs, selected state, Details/Layout split, controls, and
  trailing Add Workspace affordance at readable scale.

## Comparison history

1. **P2 resolved — the first implementation under-emphasized the selected direction's panel
   proportions and controls.** Workspace details was widened to 320 points, Duplicate/Delete became
   one balanced bordered action row, and the Layout Style and Orientation segments received a consistent
   trailing 330-point alignment. Revised wide and compact renders show a compact identity column
   beside a clearly dominant layout column without clipping.
2. **P2 resolved — the first Add Workspace affordance was narrower and visually unrelated to the
   workspace tabs.** It now shares their 168 x 126-point footprint and uses the selected mock's quiet
   dashed outline, so the end of the ordered tab strip reads as one intentional interaction.
3. **P2 resolved — a deep link or selection near the end of a long tab strip could be selected but
   remain offscreen.** The tab strip now scrolls its stable UUID into view on appearance and every
   selection change. The final nine-workspace wide and minimum-width renders show the selected
   long-name tab and Add Workspace affordance visible while earlier tabs remain horizontally
   reachable.
4. **P2 resolved — derived workspace shortcuts looked like editable shortcut controls and repeated
   the selected workspace name in two oversized rows.** They now appear under a compact Generated
   shortcuts heading as short action names with plain right-aligned read-only values. Supporting copy
   points to the editable Workspace Key above and the global Shortcuts destination for modifiers.
5. **P2 resolved — the Inner gaps and Outer screen padding equality controls used mirrored checkbox
   order and unrelated columns.** Both now use one shared label-then-checkbox row; the wide Tiled
   layout places them in the same trailing column, while compact mode retains the same stacked order.
   `windowranger-settings-workspaces-tiled-dark.png` records the exact production state.
6. **Post-fix evidence:** the final full and focused comparisons above, plus
   `windowranger-settings-workspaces-many-dark.png` and
   `windowranger-settings-workspaces-many-compact-dark.png`, contain no remaining actionable P0,
   P1, or P2 visual mismatch.

## Fidelity surfaces

- **Fonts and typography:** native San Francisco semantic headline, subheadline, caption, monospaced
  keycap, and control weights preserve the existing Settings hierarchy in Light and Dark. Long names
  remain complete in the editor and accessibility value while truncating to one line in a fixed tab.
- **Spacing and layout rhythm:** the 20-point page inset, 16-point panel rhythm, consistent 12-point
  continuous panel corners, equal workspace-tab dimensions, 320-point Details column, and flexible
  Layout/Repair column reproduce option 2's hierarchy. Minimum width stacks the same panels and keeps
  the tab strip horizontal and scrollable rather than hiding actions behind another mode.
- **Colors and visual tokens:** system window/control backgrounds, separators, semantic labels,
  orange warnings, and the user's control accent replace illustrative bitmap styling with native
  macOS Light, Dark, increased-contrast, and selection behavior.
- **Image quality and asset fidelity:** the three miniatures are native Retina vector geometry derived
  only from saved Freeform, Tiled, or Accordion style. They are intentionally abstract rather than
  screenshots of live windows; no reference bitmap, placeholder, custom icon asset, or live AX/CG
  state enters the tabs.
- **Copy and content:** every existing identity, Home Display, derived shortcut, copy, geometry,
  reset, collection, and active-workspace repair action remains present. The implementation keeps
  the real active-workspace repair command that the illustrative mock omitted.
- **Interaction and accessibility:** tab selection changes only local Settings state. Drag/drop,
  context-menu Move Left/Right, VoiceOver Move earlier/later actions, duplicate/delete, drop-to-end,
  search deep links, and UUID selection reconciliation retain the existing store operations. The
  offscreen renderer does not construct AppDelegate, register hotkeys, request Accessibility,
  contact iCloud, start the engine, order a window, or touch live windows.

## Findings and follow-up polish

- No actionable P0, P1, or P2 mismatch remains.
- **P3:** Restore Defaults remains grouped inside Workspace details rather than detached at the
  lower-left of the source. This keeps the collection action next to workspace CRUD and avoids a
  floating control at short window heights.
- **P3:** the deterministic fixture intentionally shows a real shortcut-conflict warning and the
  active-workspace recovery action, while the source is an idealized conflict-free screen. Both are
  valid product states and do not alter the selected visual-tab structure.
- Signed installed-app validation still needs pointer drag/drop, keyboard focus traversal,
  VoiceOver actions, profile switching, search deep links, and live repair behavior.

final result: passed

---

# WR-078 Shortcut Guide Target Labels Design QA

## Scope and evidence

- **Selected Navigate visual truth:**
  `/Users/chris/.codex/generated_images/01a03375-297d-7fb2-9bfc-6953d00ebee4/exec-a4a1121c-dc30-4678-8624-f94c80d1875b.png`
  (1,818 x 865 pixels).
- **Selected Arrange visual truth:**
  `/Users/chris/.codex/generated_images/01a03375-297d-7fb2-9bfc-6953d00ebee4/exec-92a16d88-f6d4-4cc6-873f-40b8a367c423.png`
  (1,817 x 866 pixels).
- **Rendered implementation:** `.build/shortcut-guide-wr078/alignment-refinement/` contains both
  families in Small, Medium, and Large, Light and Dark: 12 production-view PNGs at Retina 2x.
  Large is 1,200 x 286 points / 2,400 x 572 pixels; Medium is 920 x 230 points / 1,840 x 460 pixels;
  Small is 680 x 190 points / 1,360 x 380 pixels.
- **State:** five numbered workspaces and the complete conflict-free default action set. Snapshot
  style replaces only live desktop compositing with deterministic native material; the production
  hierarchy, typography, SF-symbol key labels, spacing, and adaptive sizing are unchanged.
- **Combined full-view comparisons:**
  `.build/shortcut-guide-wr078/comparisons/navigate-reference-above-alignment-refinement.png` and
  `.build/shortcut-guide-wr078/comparisons/arrange-reference-above-alignment-refinement.png`. Each
  input places the approved reference and final Large Dark native render together at a common
  2,400-pixel width before review.
- **Normalization:** the generated references did not obey the requested low-wide canvas and include
  surrounding black presentation space. They are width-normalized without distortion. Production
  deliberately retains WindowRanger's accepted 1,200 x 286-point Large boundary because the active
  requirement is glanceable copy without consuming more screen height.
- **Focused-region evidence:**
  `.build/shortcut-guide-wr078/comparisons/navigate-small-lower-band-before-above-alignment-refinement.png`
  compares the exact compact lower band before and after the final alignment pass. Compact fidelity
  was also checked in the original-resolution Small and Medium Light/Dark files rather than inferred
  from Large.

## Comparison history

1. **P2 resolved — Small Navigate shortened the target-bearing labels with ellipses.** The first
   680-point render showed “Previous Workspace”, “Next Workspace”, and “Last Workspace” clipping.
   Small now uses Previous, Next, and Last below the explicit **Switch Workspace** heading; Medium
   and Large retain the full labels.
2. **P2 resolved — the Arrange directional caption did not have a dependable intrinsic width.** A
   fixed size-specific directional column now keeps **Reorder by direction** complete and centred
   beneath the one arrow pad at all three densities without compressing workspace destinations.
3. **P2 resolved — a defensive mixed focus/reorder configuration fell into a generic More group.**
   If both directional command families ever share one presentation, they now retain distinct
   **Focus Window** and **Reorder Window** target headings instead of losing semantics in fallback.
4. **Final full-view result:** both families retain the approved modifier-family header, prominent
   workspace band, centred spatial caption, restrained divider, and target-labelled lower groups.
   Navigate distinguishes workspace switching from ordered window cycling; Arrange distinguishes
   focused-window changes, layout choice, and workspace display movement.
5. **P2 resolved — user-observed lower groups and keycaps were not optically centred.** Each heading,
   action pair, row, and group now centres within its allocated container instead of inheriting the
   text's leading intrinsic width. The compact **Space** keycap receives dedicated horizontal padding
   and a fixed-size label, keeping the full word readable at Small while giving it room at every size.

## Fidelity surfaces

- **Fonts and typography:** native San Francisco semantic weights match the existing guide. Family
  names remain prominent; uppercase tracked headings stay quiet; action labels keep readable optical
  weight and use compact wording only where Small genuinely needs it.
- **Spacing and layout rhythm:** the existing Small/Medium/Large panel sizes, 18-point continuous
  corner, low-wide hierarchy, equal workspace distribution, and restrained separators remain. The
  arrow caption is directly below and horizontally centred under its cluster. Lower headings and
  action rows now share the visual centre of each container, and the Space key has deliberate side
  padding instead of touching its box.
- **Colors and visual tokens:** native semantic primary, secondary, tertiary, blue accent, Liquid
  Glass, and older-system HUD fallback remain authoritative in Light and Dark. No generated colour,
  shadow, or background asset ships.
- **Image quality and asset fidelity:** all keys, arrows, dividers, type, and material are native
  vector/system output at Retina scale. The approved mockups are references only and are not embedded.
- **Copy and content:** **Navigate** and **Arrange** are unchanged. Group headings now supply the
  previously missing targets, while every visible command still comes from the same configured,
  conflict-checked registry and unavailable actions remain omitted.
- **Interaction and accessibility:** no panel policy changed. The guide remains nonactivating,
  non-key, non-main, click-through, excluded from window cycling, and hidden from accessibility so a
  held modifier cannot steal focus or create VoiceOver chatter.

No actionable P0, P1, or P2 mismatch remains. Real Liquid Glass compositing, interaction-display
placement, and press/release feel remain the signed installed-app validation boundary.

final result: passed

---

# WR-086 Quick App Shelf Shortcut Guide Design QA

## Scope and evidence

- `.build/shortcut-guide-wr086/` contains Small, Medium, and Large Light/Dark renders of the
  production Shortcut Guide view in its top-Shelf context, alongside the unchanged Navigate and
  Arrange states.
- The runtime deliberately resolves Medium to Small and Large to Medium while the Shelf is open;
  Small remains Small. This keeps the common candidate at 680 x 190 points in the free strip
  opposite a horizontal Shelf while preserving adaptive extra rows for dense workspace bindings.
- The fixture uses five workspaces and the complete conflict-free default Navigate set. Its
  snapshot material is deterministic, while layout, typography, keycaps, labels, and sizing are the
  production hierarchy.

## Review result

- The header says **Quick App Shelf**; the lower groups distinguish **Switch Workspace** and
  **Cycle Shelf Windows**; the toggle says **Hide Shelf**; ordered traversal says **Previous Shelf
  Window** and **Next Shelf Window**; and the spatial caption says **Focus Shelf Window**.
- The top-Shelf render contains only Left and Right focus keys. Policy tests separately prove that a
  side Shelf contains only Up and Down and that every edge chooses the opposite guide anchor.
- Small Dark and Medium Light were inspected at original Retina resolution. All labels remain
  complete, the two-line Shelf traversal labels are balanced within their group, separators and
  headings retain the accepted WR-078 alignment, and native Light/Dark semantic contrast remains
  legible. No P0, P1, or P2 visual issue remains.
- Live Liquid Glass compositing, free-strip placement against the actual configured Shelf size, the
  held-modifier transition as the Shelf opens/closes, and coexistence with Focus Border remain the
  signed installed-app validation boundary.

final result: passed

---

# First-run Onboarding Mission Control Design QA

## Scope and evidence

- **Selected visual truth:**
  `/Users/chris/.codex/generated_images/01a01e25-3f66-7ef1-b715-6d393aedeeaf/exec-7ccfacf0-45b6-4a8e-8d85-7730827b1aac.png`.
  The selected Option 3 direction is a compact dark native wizard with settings on the left, a
  workspace/Ranger preview on the right, cobalt Navigate accents, amber Arrange accents, and one
  restrained seven-step dock.
- **Production renders:** `.build/onboarding-design-qa/implementation/` contains a 1,960 x 1,320
  Retina PNG for every production stage, numbered Welcome through Workspaces. They are generated by
  `scripts/render-onboarding-previews.sh` from the same SwiftUI hierarchy the app presents.
- **Rendering boundary:** the isolated test host never creates AppDelegate, registers hotkeys,
  requests Accessibility, contacts iCloud, or orders a window onto the desktop. The Accessibility
  fixture therefore shows the current permission state but does not exercise the system prompt.
  The app adds a standard native title bar outside this fixed content size so its traffic-light
  controls never overlap the branded header.

## Comparison history

1. **P1 resolved — generated artwork initially failed to load in the isolated test bundle:** asset
   lookup now uses the bundle containing the onboarding marker class, which resolves to the app in
   production and the non-hosted test bundle in visual QA.
2. **P1 resolved — first full-bleed artwork pass expanded the HStack and clipped the left controls:**
   a bounded GeometryReader now gives the image an exact panel frame before applying aspect fill.
   Fresh renders show complete headers, settings, footer actions, and step dock on all seven pages.
3. **P2 resolved — the Shelf stage described an order without exposing one:** native up/down actions,
   disabled edge states, and a visible one-to-four capacity now match the actual profile-owned shelf
   policy.
4. **P2 resolved — a future wizard version could inherit an earlier in-progress stage:** resume keys
   now include the injected onboarding version, while completion remains a single monotonically
   compared version marker.
5. **P1 resolved after signed trials — trailing controls looked available but did not act:** the
   first hit-target correction did not fix the fault. Live accessibility geometry then showed the
   decorative artwork owned a 702-point hit surface that overlapped the controls column by 101
   points, covering the shortcut menus' right edge, Focus Border switch, and colour well while
   ending above the working footer. The artwork is now constrained to the right column, clipped,
   and pointer-transparent; shortcut menus use their earlier native treatment and omit modifier
   combinations invalid against the other current family. The signed retest confirmed the complete
   menu targets, switch, and colour picker all respond.
6. **P2 resolved after the first signed trial — card emphasis and Shelf guidance felt synthetic:**
   the thick leading stripe is replaced by a restrained accent wash and uniform hairline. Shelf copy
   now explains cross-workspace access, removes the redundant Skip action, and makes later setup in
   Settings explicit. iCloud and Focus Border switches use a consistent trailing control column.

## Fidelity surfaces

- **Hierarchy and geometry:** the implementation keeps the selected left-control/right-preview
  split, fixed native window, persistent header, compact centred step dock, Back, and default
  Continue/Finish action. Long or dense content scrolls only inside the left pane.
- **Colour and material:** one midnight/graphite shell carries system semantic text and controls.
  Cobalt identifies navigation and the active step; amber identifies window arrangement. Generated
  scenes are cropped within a rounded preview instead of imposing text or controls from the mock.
- **Typography and controls:** native San Francisco, SF Symbols, menus, switches, buttons, segmented
  controls, and ColorPicker preserve macOS interaction and accessibility rather than reproducing
  generated UI chrome as pixels.
- **Content and state:** each stage reads and mutates the existing SettingsStore owner. Only local,
  versioned progress belongs to onboarding. The visual fixtures include realistic Shelf entries and
  render every stage rather than testing one showcase screen.
- **Asset quality:** seven 1536 x 1024 project-bound ImageGen scenes use the canonical Ranger and dark
  normalized backgrounds. The durable source images live under
  `Brand/WindowRanger/characters/onboarding/`; catalog copies are production build inputs.

No scoped P0, P1, or P2 visual mismatch remains in the corrected renders. A refreshed signed
first-run trial must still verify shortcut-menu selection, complete menu-bar row hit areas, system
permission handoff, keyboard traversal, application picking, and completion/resume feel.

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

# Superseded Workspace Settings Master-List QA (Historical)

This section previously recorded the accepted master-list-plus-inspector Workspaces design. That
interface and its List/table-row-specific evidence were intentionally replaced by the maintainer's
selected WR-066 option 2 visual-tab design. It is retained only as a historical milestone and is not
a current acceptance record.

The authoritative current evidence, findings, render paths, accessibility language, and
`final result` are in **WR-066 Workspace Visual Tabs Design QA** above.

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

---

# Settings Sidebar Profile Context Design QA

## Scope and evidence

- **Selected visual direction:**
  `/Users/chris/.codex/generated_images/01a01e25-3f66-7ef1-b715-6d393aedeeaf/exec-9ee48805-1f2f-4007-adda-769816578aa6.png`
  (1,487 x 1,058 pixels).
- **Latest signed-app reference:**
  `/var/folders/2m/r4qlm8w914x16pc440r40nr00000gn/T/codex-clipboard-273cef50-a099-49dd-92ef-c66eb3cfe420.png`
  (283 x 119 pixels in Dark appearance). This live crop is the visual truth for selector alignment.
- **Latest open-menu reference:**
  `/var/folders/2m/r4qlm8w914x16pc440r40nr00000gn/T/codex-clipboard-13921e8d-caac-40d0-90fa-0354282f586a.png`
  (453 x 191 pixels in Dark appearance). This signed-app crop is the interaction truth: the profile
  choices must appear directly rather than behind the visible **Editing Profile** submenu.
- **Production implementation:**
  `.build/settings-redesign-previews/windowranger-settings-quickAppShelf-dark.png`
  (2,880 x 2,048 pixels for the 1,440 x 1,024 point native Settings view at 2x Retina scale).
- **Combined comparison input:**
  `.build/settings-redesign-previews/profile-selector-live-alignment-comparison.png`. The 2x
  production sidebar is cropped and normalized to 119 pixels high beside the live 283 x 119 crop;
  both show the same Dark appearance, closed selector, and destination-row state.
- **Additional states:** active-profile Workspaces, inactive-profile Quick App Shelf, Menu Bar,
  and minimum-size Quick App Shelf renders were inspected from the same production snapshot pass.

## Comparison history

1. **P1 resolved — duplicated profile ownership:** the first implementation left a second profile
   picker and activation action inside Menu Bar. The sidebar is now the only place that changes the
   Settings edit target; Profile Status owns explicit activation.
2. **P2 resolved — missing compact evidence:** Quick App Shelf was absent from the minimum-window
   snapshot loop. It is now rendered with the other Settings destinations, exercising the sidebar
   context and the shelf form together at the supported compact size.
3. **P2 resolved — intrinsic menu width:** the first sidebar menu remained only as wide as its text.
   The production button now occupies the same 220-point row width as Displays, includes the chosen
   profile icon and name, and has a trailing menu indicator in Light, Dark, wide, and compact states.
4. **Final review:** the repeated full-width context strip has been removed from Displays,
   Workspaces, Applications, and Quick App Shelf. Each page begins directly with its own content,
   while the selector remains stable beside the four profile-owned destinations. The former sidebar
   **Use Profile** row is absent.
5. **P2 resolved — signed-app row alignment:** the installed candidate exposed the fixed-width
   selector 16 points to the right of the destination-row bounds, clipping its trailing edge. The
   menu now compensates for the sidebar section's custom-row inset. The revised native Dark render
   shows the selector and Displays row sharing the same outer bounds and aligned label content.
6. **P2 implemented, live capture pending — nested picker submenu:** the aligned signed candidate
   opens an intermediate **Editing Profile** submenu. The nested picker now uses its native inline
   style so the profile choices occupy the outer menu while retaining selection checkmarks and
   profile icons. The corrected open state cannot be captured until a new signed candidate is
   installed, so interaction fidelity remains blocked rather than inferred from the closed render.

## Fidelity surfaces

- **Typography:** native macOS section labels, menu-picker text, caption status, and destination
  rows preserve the existing Settings hierarchy and remain readable in Light and Dark appearances.
- **Spacing and geometry:** the profile control fills the established 220-point destination-row
  width inside the 240-point sidebar. Its custom row compensates for SwiftUI's 16-point section
  inset, so the control no longer shifts or clips at the sidebar edge. Its placement directly above
  the four owned destinations makes the relationship clear without increasing the window width.
- **Colour and material:** semantic sidebar materials, secondary status colour, and the system
  control accent carry through native appearance and accessibility settings.
- **Image quality and assets:** all icons are real SF Symbols and all controls are native; no
  generated bitmap or recreated visual asset is shipped in the app.
- **Copy and state:** **Editing Profile**, **Active on This Mac**, and the Profile Status activation
  action keep editing and activation distinct. Profile Status edits icon and name directly; the
  selector has a VoiceOver label and an explicit hint that selection does not activate the desktop.

## Final findings

No closed-state P0, P1, or P2 mismatch remains in the scoped sidebar-profile-context pass. The latest
live-reference comparison confirms the selector and destination-row bounds are aligned. A revised
signed open-menu capture is still required to close the intermediate-submenu finding. The
reference omits WindowRanger's real Displays destination and uses a wider illustrative sidebar;
production intentionally retains both the real destination and the established native window
proportions. The production profile library and status render also confirm the selected profile icon
in the list, selector, and icon editor. Pointer use, long profile names, VoiceOver menu interaction,
inline name commit behavior, and activation against a signed running app remain live-validation
boundaries.

final result: blocked

---

# Modifier-held Shortcut Guide Design QA

## Scope and evidence

- **Selected visual truth:**
  `/Users/chris/.codex/generated_images/01a01e25-3f66-7ef1-b715-6d393aedeeaf/exec-d7e0739e-4d74-4a50-92da-f74495587ea9.png`
  (1,487 x 1,058 pixels). The selected option is the low, wide bottom key map; its illustrative
  Settings/sidebar background is context rather than a product asset.
- **Production renders:**
  `.build/shortcut-guide-design-qa/implementation/windowranger-shortcut-guide-navigation-dark.png`
  (2,400 x 572 pixels for the 1,200 x 286-point Large production view at 2x Retina scale) and
  `.build/shortcut-guide-design-qa/implementation/windowranger-shortcut-guide-movement-dark.png`
  (2,400 x 436 pixels for the compact movement state).
- **Focused comparison:**
  `.build/shortcut-guide-design-qa/comparisons/focused-side-by-side.png`
  (2,464 x 294 pixels). The reference HUD crop and implementation are normalized to the same
  1,232 x 294-pixel region and the same Control-Option navigation state.
- **Full comparison:**
  `.build/shortcut-guide-design-qa/comparisons/full-side-by-side.png`
  (2,974 x 1,058 pixels). It compares the complete reference viewport with the production HUD at
  the same bottom-centre screen anchor on a neutral dark desktop canvas.
- **Rendering boundary:** AppKit's public `NSGlassEffectView` does not rasterize in a detached
  `ImageRenderer`. The comparison therefore replaces only the offscreen surface with SwiftUI's
  native system material; the live production panel still uses Liquid Glass on macOS 26 and the
  system HUD material on older supported macOS releases.

## Comparison history

1. **P1 resolved — first pass was too small and toolbar-like:** the initial implementation used
   compact workspace cards in a 570-point panel. The selected direction instead needs a low,
   screen-spanning keyboard map. Small, Medium and Large now use 680, 920 and 1,200-point widths.
2. **P2 resolved — workspaces lacked the selected visual hierarchy:** workspace destinations now
   use prominent keycaps with their names below. Numbered names become explicit **Workspace 1**
   copy; lettered or named workspaces retain their real profile names.
3. **P2 resolved — arrow commands competed with the action row:** one truthful focus or reorder
   family becomes the selected compact arrow cluster beside the workspaces. A mixed customized
   focus/reorder family remains in the labelled action row so no registered action disappears.
4. **P2 resolved — unnecessary movement-state height:** Option-Command has no default secondary
   row, so its panel removes that row's reserved height rather than leaving a large empty strip.
5. **Final comparison:** the implementation preserves the reference's modifier header, five-key
   workspace anchor, separated arrow cluster, lower action divider and bottom-centre placement. It
   is deliberately a little denser and includes the real configured Quick App command.
6. **Post-install hardening:** the ordinary key map retains the selected one-row proportions, while
   dense supported configurations add grid rows instead of clipping valid actions. A fresh Light
   and Dark render confirmed square workspace keycaps, single-line compact key labels and the same
   horizontal hierarchy after that adaptive-layout change.

## Fidelity surfaces

- **Typography:** native San Francisco weights provide one clear modifier-family header, prominent
  key labels, quiet workspace names and compact action labels. Long custom names scale and truncate
  inside their equal destination slots rather than pushing the panel off-screen.
- **Spacing and geometry:** the selected horizontal rhythm and two-row structure are retained. The
  nine anchors clamp to the resolved interaction display's visible frame with a 24-point safe
  margin; a state without secondary actions contracts vertically and dense valid configurations
  add only the rows required to keep every action visible.
- **Colour and material:** semantic primary/secondary colours and the user's control accent sit on
  public Liquid Glass or system HUD material. Light and Dark offscreen renders were inspected; no
  reference gradient or wallpaper is copied.
- **Image quality and assets:** every key, arrow and label is native text/SF-symbol output at Retina
  scale. The generated bitmap is not embedded or shipped.
- **Content and state:** content is derived from the same conflict-checked binding registry Carbon
  registers. Numbered and lettered workspaces, disabled Command Palette state, conflicts and runtime
  registration failures therefore remain truthful rather than becoming a second hard-coded list.
- **Interaction and accessibility:** the panel is nonactivating, non-key, non-main, click-through,
  excluded from window cycling and hidden from accessibility because modifier holding alone must not
  steal focus or produce VoiceOver chatter. Release, incompatible modifiers and lifecycle stops
  dismiss it; generation checks reject stale callbacks from a previous monitor session.

No scoped P0, P1 or P2 visual mismatch remains. Live Liquid Glass compositing over varied desktop
content, multi-monitor interaction-display placement and modifier feel remain signed-app validation
boundaries.

final result: passed
