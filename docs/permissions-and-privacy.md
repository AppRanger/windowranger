# Permissions and privacy

> WindowRanger is not yet publicly released. This document
> describes current code behavior; final release copy still needs human review.

## Accessibility

WindowRanger uses macOS Accessibility APIs to enumerate eligible application windows and to read or
set attributes needed for virtual workspaces: position, size, focused/main state, raise, minimized and
full-screen safety checks. Without trust, the normal interactive app asks macOS for access. Plain
builds and the non-hosted test target do not execute that request path.

The app does not use Accessibility to read typed text or window contents. Discovery deliberately
avoids logging window titles and document names. Ignored/transient windows are rejected at the
central admission boundary and receive no workspace, layout, persistence, focus or recovery action.

Accessibility permission is controlled by macOS. WindowRanger does not reset TCC or silently alter
the system permission list.

## Launch at login

The optional **Open at login** setting uses Apple's `SMAppService.mainApp`. It is off by default for
the current installation unless the user explicitly changes it. Unit tests use an injected service
and do not register or unregister the live login item.

## Settings and iCloud

Settings sync is off by default. When **Sync settings with iCloud** is explicitly enabled, reusable
profile definitions and supported global preferences use the user's private iCloud key-value store.
Turning it off immediately stops cloud reads and writes; it does not delete local settings or
previously synced cloud data. Profile definitions can contain workspace names/keys/order/layout
geometry, abstract display-role names and typed app rules including app bundle identifiers. They do
not contain open window IDs, titles, frames, focus, monitor serials/fingerprints, the active profile
or automatic trigger assignments.

An explicitly requested profile export contains the same reusable definition boundary in a local
JSON file chosen by the user. Import is additive and does not read or write physical monitor
identities, runtime workspace/window state, permissions, diagnostics, or the active profile.

The active/manual profile selection, display-topology triggers, runtime workspace state, physical
monitor fingerprints and role bindings remain local to each Mac. iCloud can be disabled in Settings;
the app does not claim an independent cloud service or analytics backend.

## Local session state

Window membership, recoverable frames, display affinity and per-window floating overrides are saved
locally under the user's cache directory so startup/crash recovery can reconstruct the current
WindowServer session. Exact window identity is rejected after a WindowServer-session change. Normal
quit restores managed windows to visible positions before exit; a crash/debugger Stop cannot perform
that synchronous cleanup.

## Diagnostics

Debug app runs can write structured JSON Lines diagnostics to:

`~/Library/Logs/com.windowranger.WindowRanger/diagnostics.jsonl`

The file is bounded at 1 MB with two 1 MB backups. Option-clicking the status item in any build
reveals a read-only focused-window report for that menu opening. The report is capped at 64 KB,
contains a privacy-review header, uses only session-local or abstract workspace/display identities,
and includes bounded in-memory events only when they correlate to the subject window. Creating it
does not perform Accessibility writes or enable the persistent Debug log. Debug builds additionally
offer controls to copy a broader bounded excerpt or reveal the file. Opening the menu normally keeps
all support controls hidden. Debug Settings retains its Diagnostics destination. Records can
include timestamps, session/action IDs, bundle identifiers,
internal window/workspace/display IDs, short display identifiers, frames, layout decisions and AX
success/failure results.

The diagnostic privacy filter removes window titles, document names, URLs, typed content, full user
paths and window contents. A final fail-closed scrub is applied after focused-report serialization.
These exclusions are code-tested but still require manual review before a public release. Release
builds do not expose the verbose file controls or create this diagnostic file; they retain only a
small bounded in-memory history for the focused report. Minimal system fault/error reporting may
still be visible through normal macOS facilities.

Unit tests inject memory/no-op sinks and never write diagnostics into the user's home directory.

## Deliberately not collected or provided

The current app has no analytics, advertising, account system, telemetry upload, remote control,
shell-command execution or public network API. It does not intentionally collect window contents,
keystrokes, documents, browsing URLs or a history of user activity. This is a description of current
source behavior, not a substitute for final privacy review, entitlements inspection or runtime
network testing before release.
