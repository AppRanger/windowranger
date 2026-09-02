# Daily use and development on one Mac

WindowRanger's Debug configuration has a separate local development identity:

- **WindowRanger Dev**, `dev.appranger.WindowRanger.Debug`, installed at
  `/Applications/WindowRanger Dev.app`;
- **WindowRanger**, `dev.appranger.WindowRanger`, installed at
  `/Applications/WindowRanger.app` for local Release validation and public Stable/Beta builds.

macOS therefore keeps their Accessibility and Screen Recording grants separate, and their bundle
identifiers keep preferences, recovery state, diagnostics and command sockets separate. Debug is
deliberately local-only and has no iCloud entitlement, so it cannot read or change the public app's
synced profiles. Only one copy should run at a time because both copies would compete for global
shortcuts and window control. The handoff scripts stop either identity before launching the
requested one. Debug does not offer Open at Login or PATH installation, avoiding startup and
command-link conflicts with the public app; its bundled helper remains available for direct tests.

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

The default Debug install is `/Applications/WindowRanger Dev.app`. If it replaces an existing Debug
build, the previous bundle is retained at `/Applications/.WindowRanger Dev.previous` without an
`.app` suffix so LaunchServices cannot select it as a runnable app. `--release` intentionally uses
the canonical `/Applications/WindowRanger.app` identity and path for Release-configuration testing.

The Settings sidebar footer identifies the running version, build, source commit, and Dev
configuration. A daily build made from uncommitted changes appends `-dirty` to the commit so live
validation cannot accidentally be attributed to the clean commit alone.

Grant **WindowRanger Dev** once in **System Settings > Privacy & Security > Accessibility**. Keep the
existing **WindowRanger** grant for the public app. If macOS shows a stale entry after this migration,
remove only that exact stale entry and grant the app at the path above; do not use a global
LaunchServices or privacy-database reset.

## Develop in Xcode

The generated `WindowRanger` scheme automates the handoff:

1. Before Xcode runs Debug, it gracefully quits either active identity.
2. Xcode launches its exact **WindowRanger Dev** product.
3. When the Run action finishes, the scheme reopens the explicit `/Applications/WindowRanger.app`
   daily copy if it exists.

For a manual handoff, use:

```sh
./scripts/start-development.sh
./scripts/resume-daily.sh
```

`start-development.sh` opens the generated Xcode project after the active app has quit.
`resume-daily.sh` resumes `/Applications/WindowRanger Dev.app` by default; the Xcode scheme supplies
the public app path explicitly for its post-action.

Use WindowRanger's own **Quit WindowRanger** command whenever practical. Xcode's Stop button
terminates Debug without the app's normal synchronous quit cleanup; continuously saved recovery
state remains the fallback for that path.
