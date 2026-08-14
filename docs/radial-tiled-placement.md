# Radial Tiled Placement

**Status:** Implemented and automated-test verified; live layout tuning pending

## Summary

The contextual command wheel should let a user describe where the focused window should appear visually, without requiring them to understand or manipulate a binary space partitioning (BSP) tree.

In a Tiled workspace, choosing **Left**, **Right**, **Top**, **Bottom**, or one of the four corners rewrites the tiled layout structure and then performs one normal layout pass. The wheel shows the exact proposed result before the user commits it.

The interaction is inspired by the directness of Loop's visual placement controls, but its meaning is layout-aware: in Tiled mode it changes layout structure rather than assigning an independent floating frame.

## Product principles

- The user chooses a visible result; the tree remains an implementation detail.
- Placement commands are contextual and appear only when they are meaningful for the focused managed window and active layout.
- Preview and commit use the same layout calculation, so the preview does not promise a result the engine cannot produce.
- Existing layout structure should be disturbed as little as possible.
- A placement is one atomic, undoable layout transaction.
- Floating, automatically floating, excluded, ignored, minimized, and full-screen windows are never pulled into the tiled structure implicitly.
- The operation must remain deterministic across displays, gaps, padding, and minimum-size constraints.

## Implemented boundary

Tiled retains the established flat weighted appearance until placement is first used, then converts
that partition lazily into a local tree which reproduces the current rectangles. The tree is stored
per workspace/display partition only for the matching WindowServer session; it is not synced or
included in reusable profiles.

The radial menu supplies the surrounding architecture:

- a captured focused-window, workspace, layout, and display context;
- validation tokens for rejecting stale actions;
- contextual command filtering;
- a shared command dispatcher used by visual and keyboard commands; and
- a two-level, data-driven wheel definition.

The implementation consists of two pieces:

1. Add visual placement commands and previews to the command wheel.
2. Introduce a local tiled layout tree capable of representing and applying those commands.

The interaction should not be approximated by directly writing only the focused window's frame. Every commit changes layout state first and then lets the layout engine calculate all participating frames.

## Wheel interaction

The recommended command-wheel group is **Place** with eight compass-positioned choices:

```text
Top Left        Top        Top Right

Left                       Right

Bottom Left    Bottom      Bottom Right
```

When the pointer highlights a choice, an overlay previews the exact rectangles that would result from the proposed tree. No Accessibility frame writes occur during preview. Click or hold-release commits through the normal command dispatcher; Escape, a stale validation token, a missing focused window, or release in the neutral zone cancels.

The preview should emphasize the focused window and quietly outline other affected tiled windows. It should use the workspace's real display bounds, gaps, outer padding, split ratios, and safe minimum sizes.

## Placement semantics

### Edges

An edge placement promotes the focused window to a root-level region on that edge. The existing remainder of the tree is preserved as the other child.

Using `W` for the focused window and `R` for the remaining tree:

```text
Left:    leftRight(W, R)
Right:   leftRight(R, W)
Top:     topBottom(W, R)
Bottom:  topBottom(R, W)
```

The initial split ratio is 0.5, clamped when necessary by the participating windows' safe minimum sizes. A later enhancement may let repeated selection cycle through proportions such as one-half, one-third, and two-thirds.

### Corners

A corner placement is a local insertion into the region that currently owns that display corner. This preserves more of the existing layout than rebuilding the entire workspace into a fixed grid.

For **Top Left**:

1. Detach the focused window from its current leaf and collapse its now-empty parent.
2. Calculate frames for the remaining tree.
3. Find the remaining leaf whose frame contains the top-left corner of the usable display bounds.
4. Replace that leaf with a top-to-bottom split.
5. Insert the focused window above the previous corner window.

The other corner actions use the same rule:

| Choice | Corner leaf selected | Replacement split |
| --- | --- | --- |
| Top Left | Top-left | Focused window above existing leaf |
| Top Right | Top-right | Focused window above existing leaf |
| Bottom Left | Bottom-left | Focused window below existing leaf |
| Bottom Right | Bottom-right | Focused window below existing leaf |

This matches the visual idea that **Top Left** means “take whatever is currently on the left and put this window on top of that region.” Left or right selects the existing corner region; top or bottom determines which side of the new split receives the focused window.

Example:

```text
Before                         After choosing Top Left for C

+-------+-------+              +-------+-------+
|       |   B   |              |   C   |       |
|   A   +-------+      ->      +-------+   B   |
|       |   C   |              |   A   |       |
+-------+-------+              +-------+-------+

leftRight(A, topBottom(B, C))   leftRight(topBottom(C, A), B)
```

The untouched subtree retains its internal ordering and split ratios.

### What a corner does not promise

A corner choice does not always mean an exact quarter of the display. It means insertion into the existing corner region.

In a gapless rectangular tiling, one window cannot occupy an exact quarter while one other rectangular window fills the remaining L-shaped area. With only two tiled windows, a corner operation therefore naturally degrades to a top or bottom half. The preview must show this honestly. The corner choices may alternatively be hidden when the result would be indistinguishable from an edge choice.

Exact quarter-screen placement would require one of the following and is not part of this proposal:

- an empty placeholder node;
- converting the selected window to floating; or
- repartitioning several other windows across the remaining three quarters.

## Tree operation

The model can remain small:

```swift
indirect enum TiledNode {
    case window(WindowKey)
    case split(
        axis: SplitAxis,
        ratio: Double,
        first: TiledNode,
        second: TiledNode
    )
}

enum VisualPlacement {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
}
```

The placement transformation should be a pure operation over the tree:

```swift
func placing(
    _ window: WindowKey,
    at placement: VisualPlacement,
    in tree: TiledNode,
    bounds: CGRect,
    configuration: WorkspaceLayoutConfiguration
) throws -> TiledNode
```

The operation has five phases:

1. **Detach** the focused leaf.
2. **Collapse** any split left with only one child.
3. **Locate** the destination edge or corner using calculated geometry.
4. **Insert** a new split with a safe initial ratio.
5. **Validate** that every participating window occurs exactly once and every split can produce a valid rectangle.

Only after validation succeeds should the workspace adopt the new tree and issue Accessibility frame writes. If validation or application fails, retain the previous tree and emit bounded command feedback and diagnostics.

## Layout state and persistence

The tree contains runtime window identities, so it is session state rather than profile configuration:

- Keep a tiled tree per workspace and display layout partition.
- Save it with the existing local workspace/window state.
- Trust exact window identities only within the same WindowServer session.
- Do not sync trees through iCloud or copy them into reusable profiles.
- Continue syncing reusable layout settings such as gaps, padding, and default orientation.

When a flat Tiled workspace first needs a tree, convert its current order and weights into same-axis nested splits that reproduce the existing rectangles as closely as possible. This avoids visually rearranging a workspace merely because the new feature became available.

Window lifecycle rules:

- Removing a window collapses its parent and promotes its sibling.
- A new tiled window splits the focused tiled leaf; without an eligible focus anchor, it appends using the workspace's resolved orientation.
- Floating a window detaches it from the active tree while retaining the information needed to return it safely.
- Returning a window to Tiled inserts it at its remembered location when valid, otherwise beside the focused tiled window.
- Moving between workspaces or displays detaches from the source tree and inserts into the destination tree exactly once.
- Reset Workspace rebuilds a valid default tree from the current stable window order and default weights.

## Layout-aware command availability

The wheel should continue to filter from its captured context:

| Context | Placement behaviour |
| --- | --- |
| Tiled, focused participating window | Show valid tree-placement choices |
| Tiled, focused floating window | Offer Return to Layout before tiled placement |
| Freeform | Use Loop-style halves/quarters for only the focused frame; never create a tiled tree |
| Accordion | Hide corner placement; retain Accordion-specific promotion and ordering actions |
| App-rule excluded or ignored window | Hide tiled placement |
| Automatically floating dialog | Hide tiled placement unless the user explicitly forces it into the layout |
| Minimized or full-screen window | Hide or reject without moving it |

Selecting a visual placement must not silently change the workspace's layout mode.

## Diagnostics and recovery

Each preview and commit should carry the existing correlation and validation context. Useful diagnostic fields include:

- requested placement;
- workspace and display identifiers;
- focused window's internal key;
- old and proposed tree fingerprints;
- destination corner leaf;
- requested and resolved split ratios;
- validation result; and
- count of resulting Accessibility frame writes and failures.

Diagnostics must continue to exclude window titles and content.

Reset Workspace remains the recovery boundary: if session tree state is missing, stale, or invalid, rebuild from the currently admitted tiled windows rather than guessing old window identities or frames.

## Acceptance criteria

The first complete version should satisfy all of the following:

- Every committed edge action places the focused window against the requested display edge.
- Every committed corner action places it inside the existing requested corner region and against the requested two outer boundaries when the remaining structure makes that possible.
- The result contains every eligible tiled window exactly once.
- Unaffected subtrees retain their ordering and split ratios.
- Removing the focused window from its former position never leaves an empty or single-child split.
- Preview frames and committed frames are calculated from the same proposed tree.
- Preview performs no Accessibility writes.
- A stale radial context cancels rather than acting on a different window.
- One- and two-window corner cases are visually honest and deterministic.
- Floating, ignored, excluded, minimized, full-screen, parked, and other-display windows are not admitted accidentally.
- Unified and Independent Displays mutate only the intended display partition.
- Reset Workspace can recover from deliberately corrupted or stale local tree state.
- Existing flat Tiled workspaces retain their current visible arrangement when first converted.

## Implemented delivery sequence

1. Add a pure tiled-tree model, validation, flat-layout conversion, and frame calculation with unit tests.
2. Implement detach, collapse, edge insertion, and corner-leaf insertion as pure tree transformations.
3. Add placement commands to the shared command dispatcher and contextual command catalogue.
4. Add a non-writing preview path to the radial menu.
5. Commit placement atomically through the workspace engine and add correlated diagnostics.
6. Add session persistence, WindowServer invalidation, reset recovery, and multi-display tests.
7. Perform signed-app visual testing with two, three, and several real windows across both display modes.

The irreversible boundary is the first Accessibility frame-write batch. All tree calculation and preview work before that boundary should be side-effect-free and safely cancellable.
