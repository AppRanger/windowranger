# Two-Arrow Tiled Placement

**Status:** Implemented and automated-test verified; live timing/keyboard validation pending

## Implemented decision

The approved gesture combines Control-Option with two arrow directions to express a structural
Tiled placement without adding Shift. The open example starts with three columns, focuses the
middle window, and inserts it above the right-hand window.

The implemented contract is:

- Treat the pair as a **destination corner**, not as the selected window's source relationship.
- Make the two arrows order-independent: Up+Right means **Top Right**.
- For the example, use **Control-Option-Up+Right**, not Up+Left. The selected window ends in the
  top-right region and is inserted above the existing right-corner leaf.
- Reuse the existing `VisualPlacement.topRight` detach/collapse/find-corner/insert transaction and
  its zero-write preview. Do not create a second tree-reinsertion algorithm.

The four existing configurable Reorder bindings remain the only registered arrows. The composite is
derived only when all four use the same modifier family, have distinct keys, are conflict-free, and
register successfully; no hidden or competing shortcut is added.

## Evidence from established models

The references deliberately separate three ideas that can otherwise feel conflated:

1. **Directional move.** AeroSpace's current `move` traverses the tree. When the adjacent sibling
   is a container, it may move the leaf into that container; at an outer boundary it may create an
   implicit container. Its official examples make this tree-relative behavior explicit. See
   [AeroSpace `move`](https://nikitabobko.github.io/AeroSpace/commands.html#move) and source at
   [`d56e1637`](https://github.com/nikitabobko/AeroSpace/blob/d56e1637c3a1ed660d0cadd7534e94fb3218d1c3/Sources/AppBundle/command/impl/MoveCommand.swift).
2. **Swap versus reinsert.** yabai exposes leaf/node swapping separately from `warp`, which removes
   and reinserts a window at a destination node. See the official
   [window command reference](https://github.com/koekeishiya/yabai/wiki/Commands#move-window) and
   implementation at
   [`dd84572`](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/window_manager.c#L1832-L2050).
3. **Container movement.** i3's directional `move` operates on the focused container, while its
   explicit `swap` command exchanges container positions. See the official
   [i3 User's Guide](https://i3wm.org/docs/userguide.html#_moving_containers) and
   [swap section](https://i3wm.org/docs/userguide.html#_swapping_containers).

These systems confirm that a structural reinsert is meaningfully different from the existing
single-arrow reorder. Encoding the desired visible destination is clearer than asking users to
predict a BSP traversal.

## Fit with WindowRanger

WindowRanger already has eight compass `VisualPlacement` values. Corner placement:

1. detaches the focused leaf;
2. collapses its empty parent;
3. finds the remaining leaf at the requested display corner;
4. splits that leaf vertically; and
5. inserts the focused window above or below it.

For three equal columns `[A, B, C]`, with `B` focused, Top Right produces a right-side vertical
branch containing `B` above `C`. It preserves the unaffected left-side structure and performs one
validated atomic layout transaction. This is exactly the requested outcome and makes the pair's
meaning match the command wheel's compass language.

Using Up+Left for that result would encode an invisible source or insertion relationship and would
conflict with the visible meaning of the existing Top Left placement.

## Input state machine

The pure recognizer feeds the existing `VisualPlacement` proposal and commit path:

1. Control and Option must already be held.
2. The first arrow arms a candidate and captures the focused window, workspace/display partition,
   tree fingerprint, and generation. It does not mutate the tree.
3. An orthogonal second arrow pressed within **200 ms** resolves one of the four corners. Arrow
   order does not matter: Up+Right and Right+Up are both Top Right.
4. A same-axis or opposite arrow is not a composite. It cancels the candidate safely.
5. Releasing the first arrow or reaching the 200 ms timeout without a valid second arrow dispatches
   the ordinary single-arrow structural move exactly once. This retains boundary/no-op feedback.
6. A valid pair commits the already-captured proposal when the second direction arrives. This is one
   tree mutation and one normal layout pass; the first direction is never applied and undone.
7. Escape, modifier release, focus/workspace/display/profile change, sleep, or a newer action cancels
   without committing. Auto-repeat cannot create another candidate while one is pending.

The 200 ms value is the migration-safe starting point for live tuning. Carbon supplies the existing
registered arrows' public press/release events. A temporary public AppKit global monitor observes
only competing input while a candidate is pending and is removed immediately afterward; it does not
suppress or replay keys and uses the app's existing Accessibility trust path. If observation cannot
start, the app fails closed to the normal single-arrow command and reports the limitation in
Settings rather than requesting another permission.

## Why not target-direction plus insertion-side?

An ordered grammar such as Right then Up (“target the right neighbour, insert above”) describes the
example accurately but has three drawbacks:

- order becomes a hidden part of the command;
- Up then Right could appear equivalent while producing something else; and
- it duplicates the already-established compass placement vocabulary.

If future workflows need “insert relative to this exact neighbour” rather than “place at this
visible corner,” that should be a separately named reinsert command with preview, not an overloaded
two-arrow default.

## Verified acceptance boundary

- Every orthogonal pair maps to the matching `VisualPlacement` corner in either key order.
- The three-column Top Right example produces the focused middle window above the former right leaf.
- Proposal and commit have the same tree fingerprint; proposal performs zero Accessibility writes.
- A timeout/release dispatches one and only one existing single-arrow move.
- Same-axis, opposite, repeat, stale-context, workspace/display change, and Escape cases cancel or
  fall back deterministically.
- Focus stays on the moved window; only its current workspace/display partition changes.
- Floating, excluded, ignored, minimized, full-screen, parked, and other-display windows remain
  outside the placement transaction.

Automated coverage exercises both arrow orders, all four corners, release and timeout fallback,
invalid/repeated/competing input, shortcut-family failure, the three-column middle-to-Top-Right case,
nested subtree preservation, WindowServer-session persistence, display-partition scoping, and exact
focus retention. The remaining boundary is physical-keyboard timing and feel in the signed Debug app.
