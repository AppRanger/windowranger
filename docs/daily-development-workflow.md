# Daily use and development on one Mac

WindowRanger's Debug and Release configurations currently share the
`com.windowranger.WindowRanger` bundle identifier, but they do not have one interchangeable signed
identity. Xcode uses Apple Development while public packages use Developer ID; their designated
requirements differ, so macOS may maintain separate Accessibility trust decisions. Switching
between them can require removing a stale entry and granting the exact copy being launched. Only
one copy should run at a time because both copies would compete for global shortcuts and window
control.

A future development-only bundle identifier may make the two local clients unambiguous, but that is
a separate product/signing change. Stable and Beta releases continue to use the canonical public
identifier. Do not change signing, reset TCC globally, or invent another release-channel identity as
part of ordinary local handoff.

“Daily copy” describes the locally installed app used on this Mac; it is not a release channel. A
Release-configuration build from `develop` is still a Dev build, not a Stable release. Channel and
promotion rules are defined in [Release channels and branching](release-channels-and-branching.md).
The daily installer may use Apple Development signing and must never supply a public download; use
the separate [first GitHub release runbook](first-github-release.md) for distribution.

## Install or update the daily copy

The installer builds and verifies the app before stopping the currently running copy. Until the
Release configuration is ready, its default is a signed Debug build:

```sh
./scripts/install-daily.sh
```

When Release is ready, use:

```sh
./scripts/install-daily.sh --release
```

The installed app is `/Applications/WindowRanger.app`. If it replaces an existing daily build, the
previous bundle is retained at `/Applications/.WindowRanger.previous` without an `.app` suffix so
LaunchServices cannot select it as a runnable app.

The Settings sidebar footer identifies the running version, build, source commit, and Dev
configuration. A daily build made from uncommitted changes appends `-dirty` to the commit so live
validation cannot accidentally be attributed to the clean commit alone.

If the installed Developer ID build is already trusted but the Xcode build is not, open **System
Settings > Privacy & Security > Accessibility**, remove only the stale WindowRanger entry when
necessary, launch the intended exact build, and grant that copy. Repeat the handoff for the installed
copy if macOS later asks again. Do not use a global LaunchServices or privacy-database reset.

## Develop in Xcode

The generated `WindowRanger` scheme automates the handoff:

1. Before Xcode runs Debug, it gracefully quits any active WindowRanger.
2. Xcode launches its exact Debug product.
3. When the Run action finishes, the scheme reopens the explicit `/Applications/WindowRanger.app`
   daily copy if it exists.

For a manual handoff, use:

```sh
./scripts/start-development.sh
./scripts/resume-daily.sh
```

`start-development.sh` opens the generated Xcode project after the active app has quit.

Use WindowRanger's own **Quit WindowRanger** command whenever practical. Xcode's Stop button
terminates Debug without the app's normal synchronous quit cleanup; continuously saved recovery
state remains the fallback for that path.
