# Contributing to WindowManager

WindowManager is a pre-release native macOS project and the product name is provisional. The
repository is being prepared for later open sourcing; these instructions document the current safe
development workflow, not a promise of public compatibility.

## Requirements

- macOS 14 or later
- Xcode matching the checked-in project settings
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) only when `project.yml` or source membership changes
- A personal Development Team for an interactive signed build

Generate the project only when needed:

```sh
xcodegen generate
```

Do not change the bundle identifier or create a parallel Debug identifier merely for convenience.
Accessibility trust is attached to the signed app identity, and duplicate/stale products make live
testing unreliable.

## Code style

- Prefer small typed models and pure decision functions before AppKit/AX side effects.
- Keep workspace, display, focus and layout business rules out of renderers.
- Inject system and filesystem boundaries so unit tests stay deterministic and non-hosted.
- Preserve user-owned windows on uncertainty: ignore/defer rather than guessing a destructive frame.
- Use privacy-safe identifiers in diagnostics; never add titles, document names, URLs, typed content,
  full user paths or window contents.
- Keep synced profile content and machine-local/session state explicitly separate.

## Safe test workflow

Use focused non-hosted tests while iterating, then the full suite once at a checkpoint:

```sh
./scripts/verify-test-isolation.sh
xcodebuild -project WindowManager.xcodeproj \
  -scheme WindowManager \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The Test action must continue to report only `WindowManagerTests` in its dependency graph. It must
not build, host or macro-expand `WindowManager.app`. Tests must not register Carbon hotkeys, prompt
for Accessibility, change login items, access iCloud, write diagnostics in the user's home directory,
or inspect/move live windows.

For implementation checkpoints:

1. run the smallest relevant test class;
2. run the complete non-hosted suite once the subsystem is coherent;
3. build signed Debug only for a live-test candidate;
4. reserve universal Release, signature, LaunchServices and privacy-boundary checks for a milestone.

Do not use disposable app build directories: macOS/Xcode can register every built app with
LaunchServices. Use the canonical Xcode DerivedData product for app builds and the non-hosted target
for background tests.

## Live-window safety

Never launch, stop, replace or automate a user's running WindowManager while doing background
verification. Do not reset TCC, alter Accessibility permissions, mutate the real login-item state or
move/resize user windows from tests. A human live test must begin by gracefully quitting the old
build through its menu, then running the intended signed Debug product from Xcode.

Xcode Stop is a hard termination and does not test graceful window restoration. Use **Quit
WindowManager** when validating quit recovery.

## Changes and review

- Add deterministic tests for each new decision and regression.
- Update README/docs and the canonical feature roadmap with built/tested/live-pending truth.
- Keep commits scoped to one logical checkpoint and do not include DerivedData, `.build`, app bundles,
  logs, screenshots not intended as docs, credentials or machine-specific paths.
- Treat crashes, data loss, privacy/security and testing blockers as immediate; otherwise group bugs
  at a safe subsystem checkpoint.

Before a public contribution process is announced, issue/PR templates, support channels and release
expectations remain intentionally unspecified.
