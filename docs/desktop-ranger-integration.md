# WindowRanger integration with DesktopRanger

Status: **Approved product direction; CLI and adapter are not yet implemented public contracts**

Date: 23 August 2026

This document records WindowRanger's ownership and contract boundary for first-class integration
with DesktopRanger. It does not make the current pre-release command internals a compatibility
promise. A canonical `WR-###` implementation item must define the exact schema and evidence gates
before the CLI is shipped.

DesktopRanger's corresponding decisions are in
`DesktopRanger/docs/first-party-content-plan.md` and
`DesktopRanger/docs/product-technical-spec.md` in the DesktopRanger repository.

## Product ownership

WindowRanger remains authoritative for:

- window discovery and admission;
- focus and window actions;
- workspaces and their active state;
- layouts and placement;
- profiles and display-role binding;
- Quick App Shelf state and exact-window ownership;
- window groups, restore, recovery, and Pause/Reset behaviour.

DesktopRanger owns scriptable surfaces, plugins, data composition, first-party starters, and its
plugin capability boundary. It may display WindowRanger state and invoke WindowRanger operations,
but it does not reproduce WindowRanger's engine or read WindowRanger's private files.

## Shared command direction

WindowRanger has a typed command dispatcher shared by hotkeys and the Command Palette, but not every
current menu or presentation path routes through it. CLI work must first converge each deliberately
exposed operation onto one validated gateway and engine path. The planned CLI then becomes another
consumer of that gateway rather than a wrapper around direct UI actions or a second command
implementation.

The same command vocabulary should be reusable, where appropriate, by:

- WindowRanger hotkeys, menus, Command Palette, and future App Intents/Shortcuts;
- the versioned non-interactive `windowranger` CLI;
- DesktopRanger's host-owned `windowRanger` adapter;
- DesktopRanger first-party plugins such as Ranger Control and App Shelf;
- explicit local automation that preserves the same availability and validation rules.

Presentation-specific commands can remain app-internal. Exposing a command is an intentional API
decision, not an automatic consequence of its presence in the in-process dispatcher.

## Structured CLI requirements

The CLI must be automation-safe rather than a text scraper for the app UI:

1. Non-interactive operation with versioned JSON request, response, event, and error envelopes.
2. Stable command identifiers and input/output schemas distinct from localized titles.
3. A version/feature handshake and explicit compatibility result.
4. Separate query and mutation operations with current-context availability checks.
5. Bounded output, deadlines, cancellation behaviour, and deterministic exit categories.
6. Idempotency or operation identifiers where retries could otherwise duplicate a mutation.
7. Privacy-safe output by default: no window titles, document names, URLs, paths, typed content, or
   other sensitive values unless a narrowly scoped operation and user decision explicitly require
   them.
8. Structured unsupported, unavailable, Accessibility required/denied, degraded, stale-state,
   conflict, timeout, and internal-failure results.
9. No dependence on an interactive terminal, shell profile, inherited secrets, or localized prose.
10. Tests proving that CLI dispatch and in-app dispatch use the same validation and engine paths.
11. A thin-client model: the CLI sends requests to the one running WindowRanger app instance and
    never starts a second workspace engine, mutates persistence independently, or treats state files
    as an IPC surface.
12. Same-user authenticated local IPC with a verified WindowRanger bundle identity and designated
    signing requirement; a merely signed executable, matching filename, or bundle identifier is not
    sufficient.
13. Explicit semantics for no running instance, app launch/relaunch during a request, concurrent
    clients, duplicate/replayed operation identifiers, late replies, and owner-session change.

The first contract should be deliberately small. Candidate operations include reading app/version
and capability state; listing opaque profile/workspace identifiers and non-sensitive state; reading
current workspace/profile/display-role state; activating an existing profile or workspace; invoking
a bounded existing layout command; showing/hiding/cycling a configured Quick App Shelf entry; and
requesting existing host-owned recovery actions where safe. Profile and workspace labels are
user-authored data, not intrinsically privacy-safe metadata; returning them requires an explicit
declared/read grant plus bounded redaction and diagnostic rules.

## DesktopRanger adapter boundary

DesktopRanger plugins do not invoke the CLI. The DesktopRanger host owns:

- discovery of the signed WindowRanger installation and compatible CLI;
- verification of the expected bundle identity, designated signing requirement, resolved executable
  location, and same-user IPC peer before every trust-bearing connection or launch;
- process launch with an explicit environment and no ambient shell;
- request construction, output and resource limits, timeout, and cancellation;
- response-schema and compatibility validation;
- operation attribution, diagnostics, and failure redaction;
- mapping to bounded typed `windowRanger` adapter operations;
- DesktopRanger capability checks separating observation from control.

Discovery and verification must resist path substitution and check/use races. The host does not
trust a PATH result, mutable symlink, matching filename, arbitrary signed binary, or stale earlier
verification. It communicates with the single WindowRanger app owner and never creates a competing
workspace engine.

This keeps transport details and process authority out of plugin code. The transport can later move
to another supported local mechanism without changing first-party plugin APIs.

## First-party consumers

### Ranger Control

The DesktopRanger Ranger Control plugin may present available profiles, workspaces, layouts,
window-group actions, Quick App Shelf commands, and restore/recovery actions. It reflects
WindowRanger's availability and never creates a second persisted source of truth.

### DesktopRanger App Shelf

DesktopRanger's App Shelf is distinct from WindowRanger's Quick App Shelf:

- **Quick App Shelf** is WindowRanger-owned exact-window presentation for up to four configured
  profile-aware applications.
- **App Shelf** is a DesktopRanger-rendered alternative app/command surface that may combine pinned
  apps, running apps, plugin commands, and WindowRanger-supplied window/workspace actions.

App Shelf consumes only the bounded state and commands WindowRanger deliberately exposes. It does
not enumerate or control windows independently when WindowRanger is the owner.

## macOS protection and system-UI boundary

Neither product requires disabling System Integrity Protection, Gatekeeper, Hardened Runtime,
library validation, or another macOS protection. The integration does not patch, inject into,
replace, suppress, or assume ownership of the Dock, menu bar, Control Centre, Notification Centre,
Finder desktop, login window, or lock screen.

DesktopRanger App Shelf is an independent surface, not a Dock replacement. A user may choose macOS
Dock auto-hide in System Settings, but Ranger does not silently change that preference. The Apple
Dock remains enabled and reachable if either Ranger app pauses, quits, crashes, or is uninstalled.

## Sequencing and acceptance

Before the integration is described as available:

1. Promote the CLI into a canonical WindowRanger `WR-###` item with exact scope and migration policy.
2. Define the versioned envelope, initial command allowlist, privacy model, and compatibility rules.
3. Converge every exposed UI and CLI operation onto shared validation and single engine ownership;
   retain direct presentation paths only when they are intentionally not part of the CLI contract.
4. Test missing app/CLI, version mismatch, malformed request, invalid output, timeout, cancellation,
   wrong signer/path substitution, peer rejection, Accessibility denied/revoked, stale state,
   duplicate and concurrent commands, late replies, and WindowRanger launch/relaunch.
5. Prove DesktopRanger cannot turn the CLI into arbitrary shell or argument execution.
6. Validate Ranger Control and App Shelf in signed installed builds with both apps independently
   upgraded, unavailable, paused, crashed, and removed.
7. Confirm that integration failure never changes the Apple Dock or weakens a macOS protection.

Until those gates pass, fixtures may demonstrate the DesktopRanger experience but must label the
WindowRanger integration unavailable or simulated.
