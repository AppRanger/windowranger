# Portable profile transfer design

Status: implementation contract for the first JSON export/import increment.

## Goal

Let a user move reusable WindowRanger profile definitions between Macs without creating a second
configuration source or leaking machine/session state. Import is additive, previewed, atomic and
never activates a profile or moves a window.

## Portable boundary

The versioned document contains an ordered collection of `WindowManagerProfile` definitions:

- profile name, Settings icon, and reusable identity relationships;
- ordered workspace definitions, keys, layouts and geometry;
- Unified or Independent Displays mode;
- abstract display roles, their menu-bar icon choices, and workspace-to-role assignments;
- complete typed application rules, including enabled/paused state;
- the ordered Quick App Shelf of up to four apps and its shared presentation.

It deliberately excludes the active or manually pinned profile, automatic trigger mappings
(including the local foreground full-screen Game Mode target),
runtime active-workspace state, physical display identifiers/fingerprints and role bindings, live
window membership/IDs/frames/focus, permissions, diagnostics, login-item state, and global app
preferences. Physical monitor bindings must be established locally after import.

The file is a transport document only. The profile library remains the sole authoritative settings
format and continues to use the existing iCloud/local persistence boundary.

## Format and validation

Version 1 is JSON with a fixed format identifier, an integer version, and `profiles`. Export uses
stable ordering, pretty printing, and sorted keys for reviewable diffs. Import accepts exactly the
current version; an older, future, missing, or differently identified document is rejected rather
than guessed.

The entire document is decoded and validated before any mutation. Validation rejects:

- malformed JSON or unsupported format/version;
- empty exports and duplicate profile, workspace, display-role, or per-profile app-rule identities;
- workspace-role or app-rule workspace references that do not exist in their profile;
- unsupported workspace keys, duplicate enabled workspace keys, invalid names, non-finite or
  out-of-range geometry, or contradictory duplicate rule actions;
- documents over 2 MiB, more than 64 profiles, 128 workspaces per profile, 32 display roles per
  profile, 256 app rules per profile, more than four Quick Apps per profile, invalid shared shelf
  presentation, or the documented bounded string lengths.

The bounds are defensive file-input limits, not targets for the user interface.

## Preview, remapping, and apply

After validation, the importer creates a plan against a snapshot of the current profile library.
Every imported profile, workspace, and display-role UUID is replaced with a fresh UUID. All
workspace-role assignments and typed app-rule workspace references are remapped consistently.
Imported profile names are made deterministically unique in source order (`Name`, `Name 2`, and so
on) against both existing and earlier imported names.

The native preview shows source and resulting profile names plus counts for workspaces, roles, and
rules, and explicitly says the profiles will not be selected or bound to monitors. Cancel discards
the plan. Confirm adds every planned profile in one library write. If the library changed after the
preview was created, confirm reports that the preview is stale and asks the user to import again;
it never partially applies or silently changes what was previewed.

No imported profile is activated, selected as a default, mapped to a trigger, or given a local
monitor binding. Existing profiles and all local state remain unchanged.

## Undo

Confirm registers one native Undo action. Undo removes only the exact imported definitions when
they remain byte-for-model unchanged and none has become active, manually pinned, a local default,
a dock/undock/exact trigger target, a runtime-state owner, or the owner of a locally bound role.
If later use or editing makes removal unsafe, Undo is a no-op rather than deleting user work.

## System boundaries

JSON coding/planning is pure. File reads/writes and `NSOpenPanel`/`NSSavePanel` selection are behind
injected protocols. Tests use memory or temporary-directory implementations and never show UI,
touch iCloud, start AppDelegate, install hotkeys, request Accessibility, or operate live windows.
Production export writes atomically to the URL approved by the user.

## Diagnostics and privacy

Debug diagnostics record only transfer outcome, version, bounded counts, and short generated
profile IDs. They do not record file paths, profile/workspace names, app names, bundle identifiers,
monitor identities, or window data. Release keeps the existing quiet diagnostics boundary.

## Acceptance tests

- deterministic round trip of all reusable definition fields, including the ordered Quick App Shelf
  and shared presentation;
- rejection of legacy/future/malformed/oversize/invalid-reference/duplicate-identity input;
- complete fresh-ID relationship remapping and deterministic name uniqueness;
- cancel and stale-preview paths cause no mutation;
- apply is all-or-nothing and leaves active/local/runtime state untouched;
- safe Undo removes only the profiles created by that import;
- injected panels/files prove no production UI or filesystem dependency is needed by tests;
- imported definitions persist through the existing profile-library/iCloud path only.
