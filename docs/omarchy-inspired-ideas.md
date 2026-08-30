# Omarchy-inspired ideas for WindowRanger

Status: **Product research, not committed roadmap.** `TODO.md` is the canonical queue. Every active
candidate in this note maps to a `WR-###` decision item; ideas labelled deferred are not approved
for implementation.

## Product direction

Omarchy's most transferable quality is not a particular Linux or Hyprland feature. It is the way
window management, launching, configuration, discoverability, and recovery form one coherent
keyboard-first environment.

WindowRanger should adapt that coherence to macOS rather than imitate Hyprland. Automatic tiling
stays optional, native Space behavior remains conservative, WindowRanger themes affect only its own
surfaces, and keyboard-first features remain discoverable and mouse-friendly.

## Canonical feature map

| Omarchy-inspired idea | Current WindowRanger foundation | Canonical status |
| --- | --- | --- |
| Searchable command surface and live shortcut guide | Shared command dispatch, contextual catalogue, configurable shortcuts, menus, Placement Halo/Wheel, and command feedback | [`WR-060`](../TODO.md#wr-060--searchable-command-surface) — Done |
| Quick App Shelf | Up to four ordered profile-aware Quick Apps with coordinated Accordion/Carousel exact-window presentation and recovery | [`WR-061`](../TODO.md#wr-061--quick-app-shelf) and [`WR-064`](../TODO.md#wr-064--multi-window-quick-app-shelf-presentation) — Live validation |
| Workspace personalities | Profiles plus persistent Freeform, Tiled, and Accordion behavior per workspace | [`WR-010`](../TODO.md#wr-010--tiled-layout-templates-and-builder) — topology templates extend Tiled only; broader modes remain Profiles |
| Window groups | Workspace membership and app summaries, but no explicit activity group | [`WR-008`](../TODO.md#wr-008--named-whole-desk-arrangements) — named arrangements resolved against; any future group must be distinctly session-only |
| Restore configured apps | Profile rules and explicit activation, but activation currently waits for apps/windows to appear | [`WR-088`](../TODO.md#wr-088--optionally-restore-and-launch-configured-apps-when-applying-a-profile) — refine two optional activation behaviors |
| Contextual status HUD | Shared nonactivating command-feedback overlay | Implemented by `WR-035`; extend only when a new state needs explanation |
| Scrolling layout | No current equivalent | Deferred experiment; no queue item |
| Follow-me window | Quick App display placement, but no cross-Space sticky promise | Deferred experiment; no queue item |
| WindowRanger themes | Coherent native surfaces and appearance-aware overlays | Design principle, not a standalone feature |

The menu-bar workspace application shelf is not the proposed Quick App Shelf. It previews and
focuses apps belonging to one workspace; it does not remember a personal set of summonable windows.

## 1. Searchable command surface

Define WindowRanger operations once and make them discoverable through a searchable palette that
shows the current shortcut and whether each command is available in the present context.

Potential later consumers of the same registry include:

- configurable keyboard shortcuts;
- application and status menus;
- the Command Palette and position-focused Placement Halo/Wheel;
- App Intents and Shortcuts;
- the planned versioned structured `windowranger` command-line interface;
- an optional local automation URL scheme.

The first increment resolves this as a distinct search-first presentation of the existing command
architecture. The former broad wheel is now a position-only Placement Wheel, with the same actions
available as an inline halo in the palette; both surfaces dispatch through the same typed command
gateway. The CLI is now an approved integration direction for DesktopRanger, while its exact schema,
implementation item, and acceptance evidence remain later work; see
[WindowRanger integration with DesktopRanger](desktop-ranger-integration.md). App Intents and URL
automation also remain later consumers rather than part of this increment.

## 2. Quick App Shelf

Quick App has evolved from one summoned application into a small profile-aware shelf of up to four
ordered application configurations, such as a terminal, notes window, music player, activity
monitor, or AI-agent session. The first increment established exact per-window ownership and the
Command Palette selector. `WR-064` adds a coordinated overlapping Accordion or non-overlapping
Carousel, bounded by a shelf-owned one-to-four visible maximum.

The useful version remembers a specific window when macOS exposes enough identity evidence, because
that preserves document, terminal, or browser context. It must retain the current conservative
behavior when identity is ambiguous.

Possible interaction:

- the existing shortcut shows or hides the most recently used shelf entry;
- Command Palette actions select an entry or cycle Next/Previous;
- an optional cycle shortcut is configurable but unset by default;
- Settings adds, removes, and reorders entries, capped at four with no duplicate applications;
- legacy single-Quick-App profiles migrate their existing entry to the first shelf position;
- launch and recovery reuse the existing Quick App safety boundaries, with exact ownership for each
  presented entry and no ambiguous window guessing;
- extra apps are never launched merely to fill the visible maximum; only already available,
  unambiguous neighbours join the group.

## 3. Workspace personalities through the layout model

A workspace already remembers behavior through Freeform, Tiled, and Accordion. Any personality
work should extend that established model rather than introduce a competing workspace mode.

Profiles already express broader Writing, Coding, or Presentation environments. `WR-010` should stay
inside Tiled geometry: candidate built-ins include 2x2, equal columns, and one large left slot with
two stacked right slots. Templates contain normalized slots and ratios, not application identity;
current eligible windows fill them in deterministic layout order. Built-ins and the custom builder
write topology into the workspace rather than creating another named library. Freeform remains the
native recorded-position behavior.

## 4. Profile restoration and session-only groups

Named arrangements were resolved against because Profiles already own reusable workspaces,
Application Rules, layouts, and activation. `WR-088` instead considers two independent, default-off
profile options: reconcile already-running configured apps when a profile is explicitly applied, and
launch configured apps that are missing. Automatic profile triggers should not launch apps in the
first increment.

A future temporary group could still represent windows involved in one current activity, such as
Xcode, Simulator, and documentation, but it must prove a distinct session-only interaction rather
than becoming another reusable Profile. Profile restoration should use existing App Rules and normal
window admission, preserve inactive-workspace parking, and never focus every app while reconciling.

## 5. Deferred experiments

- **Scrolling layout:** arrange windows in a strip with one or two emphasized at a time.
- **Follow-me window:** simulate a utility following the interaction display or native Space only
  where public macOS behavior is reliable.
- **WindowRanger themes:** coordinate the palette, HUD, focus border, and previews without attempting
  to theme other applications.

These remain research notes until a concrete product decision promotes one into `TODO.md`.

## Suggested decision order

1. Live-validate the corrected `WR-061` and multi-window `WR-064` Quick App Shelf across real
   profiles and lifecycle paths.
2. Decide the manual profile restoration/launch boundary in `WR-088`.
3. Decide Tiled template ownership, exact-count behavior, and builder scope in `WR-010`.
4. Revisit deferred experiments only after those foundations are settled.

## Original research sources

- [The Omarchy Manual](https://learn.omacom.io/2/the-omarchy-manual/)
- [Omarchy navigation](https://github.com/basecamp/omarchy/blob/quattro/manual/04-navigation.md)
- [Omarchy top bar and shell](https://github.com/basecamp/omarchy/blob/quattro/manual/05-the-top-bar.md)
- [Omarchy hotkeys](https://github.com/basecamp/omarchy/blob/quattro/manual/07-hotkeys.md)
- [Omarchy CLI](https://github.com/basecamp/omarchy/blob/quattro/manual/14-omarchy-cli.md)
- [Omarchy releases](https://github.com/basecamp/omarchy/releases)

Research captured on 15 August 2026; the mapping to current WindowRanger behavior was reconciled on
20 August 2026. Source links are historical research references, not a claim that current Omarchy
behavior was reverified on the reconciliation date.
