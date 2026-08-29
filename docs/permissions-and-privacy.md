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
the system permission list. While General Settings or the setup wizard is visible and access is
missing, a bounded-frequency read-only trust check updates the status after an external System
Settings change. This check never repeats the permission prompt.

## Optional workspace window previews

**Show window previews** is off by default and stored only on this Mac. Enabling it is the only
WindowRanger action that requests macOS Screen Recording access. Opening Settings, hovering a
workspace, granting Accessibility, restoring a profile, or running tests does not request that
permission. If access is denied or later revoked, previews remain available using managed-window
geometry, application icons, and privacy-safe placeholders.

When enabled and authorized, WindowRanger uses ScreenCaptureKit for bounded one-shot captures of
eligible managed windows at thumbnail resolution. It does not start a continuous screen stream,
capture audio or the pointer, or move, unpark, unminimize, raise, activate, or focus a window to make
it capturable. A protected, unavailable, stale, or parked window that cannot be captured remains a
placeholder rather than causing a window-management action.

If the option is already enabled and Screen Recording is authorized when WindowRanger launches,
startup restoration may resize eligible inactive Tiled and Accordion windows once after they have
been parked. Their parked position is retained and verified, and active, Freeform, floating,
excluded, fixed-size, deferred, minimized, full-screen, and keep-on-all-workspaces windows are not
resized. This bounded Accessibility preparation lets each application render an undistorted
thumbnail at its eventual layout size; it does not unpark, raise, activate, focus, continuously
refresh, or retain another full-resolution image.

The same opt-in may add the current wallpaper for the workspace's home display when macOS exposes a
readable desktop-image file through AppKit. WindowRanger decodes it directly to the final preview
size; it does not capture the desktop or keep a full-resolution wallpaper copy. Dynamic, protected,
or otherwise unavailable wallpaper remains the normal neutral preview background.

Preview pixels live only in a bounded in-memory cache shared by the menu-bar and Settings preview
surfaces. They are never written to profile or session persistence, iCloud, exports, diagnostics,
support reports, or logs. In-flight capture and cached pixels are discarded when the option is
disabled, permission is unavailable, the screen locks or sleeps, the login session resigns, display
topology or active profile changes, tracked preview identity or geometry changes, or WindowRanger
quits. Permission is rechecked when WindowRanger becomes active, before a menu preview is presented,
and after a capture batch completes.

## Optional trackpad workspace gesture

**Swipe between workspaces** is off by default and stored only on this Mac. When enabled,
WindowRanger uses an Accessibility-authorized, read-only Core Graphics event tap to observe generic
trackpad gesture events. It reads only the selected finger count, session-scoped touch identities,
and normalized movement needed to decide whether one horizontal swipe crossed the threshold. It
does not suppress or modify the original event, store a gesture history, log touch identities or
positions, or read typed input. All per-gesture state is discarded when the fingers lift or the
gesture is cancelled. The monitor pauses during sleep, inactive-session, shortcut-recording and
full-screen game states, and fails closed with a visible Settings issue when macOS does not expose
the gesture stream.

## Launch at login

The optional **Open at login** setting uses Apple's `SMAppService.mainApp`. It is off by default for
the current installation unless the user explicitly changes it. Unit tests use an injected service
and do not register or unregister the live login item.

## Optional command-line PATH setup

The command-line helper is bundled inside the signed app. Selecting **Add Command to PATH** creates
`~/.local/bin` when necessary, adds an exact symlink named `windowranger`, and adds a marked PATH
block to `.zprofile` or `.bash_profile` only when that directory is not already configured. The
manager refuses an existing regular file, foreign symlink, shell-file symlink, or edited/duplicate
managed block rather than replacing it. Removal owns only the exact current-app symlink and exact
managed block. This machine-local choice is never synced.
Existing startup-file permissions, ACLs, flags, and extended attributes are retained when the managed
block is added or removed. The login shell is read from the current macOS account rather than assumed
from a GUI process environment variable.

Runtime commands use a same-user Unix-domain socket and bounded versioned JSON. The app and helper
verify one another's Team ID, code identifier, and resolved executable location; finding a command
with the right name on PATH is not a trust decision. The CLI does not read WindowRanger persistence
files or start another workspace engine; the running app remains the sole authority.

The ordinary workspace list omits names unless the caller explicitly supplies `--names`. In
contrast, `config get` is an intentional complete private-data export: it can include profile,
workspace and display-role names, application bundle identifiers, shortcut choices, local physical
display bindings, automatic profile assignments, updater choices, onboarding progress and other
persisted settings. It does not include window contents, titles, document paths, live window frames,
diagnostics, permission database contents or credentials. Callers and agents should minimize its
retention and must not publish it by default. Applying it validates one complete versioned document,
requires an explicit replacement flag and rejects a stale revision before changing settings.
Whole-document apply cannot turn iCloud on. Joining iCloud uses a separately confirmed action and
then requires a fresh snapshot because an accepted existing cloud library may become authoritative.
Overwriting that cloud library with this Mac's copy uses a different exact confirmation token.

Generated agent-skill content is static and includes no live runtime state, window content, titles,
paths, profile data, configuration, or diagnostics. Skill export will not replace an existing file
without explicit `--force` and never writes through a symbolic-link destination.

## Settings and iCloud

Settings sync is off by default. When **Sync settings with iCloud** is explicitly enabled, reusable
profile definitions and supported global preferences use the user's private iCloud key-value store.
Turning it off immediately stops cloud reads and writes; it does not delete local settings or
previously synced cloud data. Profile definitions can contain workspace names/keys/order/layout
geometry, abstract display-role names and typed app rules including app bundle identifiers. They do
not contain open window IDs, titles, frames, focus, monitor serials/fingerprints, the active profile
or automatic trigger assignments.

The one atomic synced profile-library document is bounded to 750,000 encoded bytes, 128 profiles,
128 workspaces and 64 display roles per profile, 512 app rules per profile, and 256 characters per
user-facing name. WindowRanger checks the byte bound before decoding and validates version, counts,
names and structure before replacing local definitions. Rejected remote data remains untouched in
iCloud, existing local/private-install profiles remain available without silent truncation, and
General Settings presents the rejection plus an explicit replace-cloud-with-local recovery action
when the local document is eligible.

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

`~/Library/Logs/dev.appranger.WindowRanger/diagnostics.jsonl`

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

The current app has no analytics, advertising, account system, telemetry upload, remote network
control, arbitrary shell-command execution, or public network API. It does not intentionally collect window contents,
keystrokes, documents, browsing URLs or a history of user activity. This is a description of current
source behavior, not a substitute for final privacy review, entitlements inspection or runtime
network testing before release.
