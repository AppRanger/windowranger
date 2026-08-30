# Contributing to WindowRanger

Thank you for considering a contribution. WindowRanger is a pre-release native macOS project that
controls real windows through Accessibility APIs, so changes must favour user safety, predictable
behaviour, and honest validation over breadth.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) before participating. For help using or
building the project, see [Support](SUPPORT.md). Do not report vulnerabilities in a public issue;
follow the [Security Policy](SECURITY.md) instead.

## Before you start

- Search the existing issues and the [work queue](TODO.md) before opening a duplicate.
- Use an issue to propose new features, broad refactors, new dependencies, persistence changes, or
  changes to window-management behaviour before investing in an implementation.
- Small, well-scoped bug fixes, tests, and documentation improvements may go directly to a pull
  request.
- Keep pull requests focused on one coherent outcome. Maintainers may ask for unrelated changes to
  be split out.
- Native macOS Spaces integration is an explicit non-goal. Items in the work queue marked
  **Needs decision** or **Held** are not approved implementation work.
- Read the [release channels and branching](docs/release-channels-and-branching.md) contract before
  choosing a branch base or proposing release, versioning, update, or packaging changes.

Opening an issue does not guarantee that a proposal will be accepted. Early discussion is intended
to avoid wasted effort and establish the product and safety boundaries first.

## Development setup

You need:

- macOS 14 or later;
- Xcode compatible with the checked-in project settings;
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) when `project.yml` or source membership changes;
- a personal Apple Development Team for interactive signed builds.

Clone the repository, then generate the Xcode project only when needed:

```sh
git clone https://github.com/AppRanger/windowranger.git
cd windowranger
xcodegen generate
open WindowRanger.xcodeproj
```

Select your Development Team and run the `WindowRanger` scheme. The app requests Accessibility
access on first launch. iCloud key-value sync requires a signed build with the iCloud capability
available to the selected team.

If you also use an installed daily copy on the same Mac, follow the
[daily development workflow](docs/daily-development-workflow.md) so only one copy runs at a time.

Do not change the bundle identifier or create a parallel Debug identifier for convenience.
Accessibility trust is attached to the signed app identity, and duplicate or stale products make
live testing unreliable. Quit AeroSpace or other window managers before testing overlapping global
shortcuts.

## Implementation principles

- Prefer small typed models and pure decision functions before AppKit or Accessibility side effects.
- Keep workspace, display, focus, and layout business rules out of renderers.
- Inject system and filesystem boundaries so unit tests stay deterministic and non-hosted.
- Preserve user-owned windows on uncertainty: ignore or defer rather than guessing a destructive
  frame.
- Never write a frame before central admission and current-context validation.
- Keep reusable synced profile content, machine-local settings, and WindowServer-session state
  explicitly separate.
- Use privacy-safe identifiers in diagnostics. Never add window titles, document names, URLs, typed
  content, full user paths, or window contents.
- Add deterministic tests for new decisions and regressions. Update documentation when behaviour or
  safety boundaries change.

The [architecture guide](ARCHITECTURE.md) documents the system boundaries and invariants in more
detail.

## Test safely

Run focused non-hosted tests while iterating, then run the full suite at a coherent checkpoint:

```sh
./scripts/verify-test-isolation.sh
xcodebuild -project WindowRanger.xcodeproj \
  -scheme WindowRanger \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The Test action must report only `WindowRangerTests` in its dependency graph. It must not build,
host, or macro-expand `WindowRanger.app`. Tests must not register Carbon hotkeys, prompt for
Accessibility, change login items, access iCloud, write diagnostics in the user's home directory,
or inspect or move live windows.

The repository packages that same safe checkpoint as:

```sh
./scripts/verify-local-ci.sh --quick
```

To run it automatically against the exact commit being pushed, opt this clone into the
repository-managed pre-push hook:

```sh
./scripts/install-git-hooks.sh
```

The hook validates one pushed commit in a temporary detached worktree, so uncommitted files in the
active checkout cannot enter its result. It performs only project generation, shell syntax, test
isolation, and the non-hosted suite; it never builds, launches, stops, signs, installs, or automates
WindowRanger. Hook installation is deliberately local and opt-in because Git does not install hooks
from a clone. Remove it with `./scripts/install-git-hooks.sh --remove`. If the clone already has a
different `core.hooksPath`, the installer stops rather than overwriting it.

At an integration or release checkpoint, run the heavier local equivalent explicitly:

```sh
./scripts/verify-local-ci.sh --full
```

Full verification adds Release static analysis, an unsigned Release build in canonical DerivedData,
and Stable/Beta DMG smoke creation and verification. It remains uncredentialed: signing,
notarization, publication, installation, and live-window testing are separate maintainer actions.

For implementation checkpoints:

1. Run the smallest relevant test class.
2. Run the complete non-hosted suite once the subsystem is coherent.
3. Build signed Debug only for a deliberate live-test candidate.
4. Reserve universal Release, signature, LaunchServices, notarization, and privacy-boundary checks
   for a release milestone.

Do not use disposable app build directories. macOS and Xcode can register every built app with
LaunchServices. Use the canonical Xcode DerivedData product for app builds and the non-hosted target
for background tests.

## Live-window safety

Never launch, stop, replace, or automate a contributor's running WindowRanger during background
verification. Do not reset TCC, alter Accessibility permissions, mutate the real login-item state,
or move or resize user windows from tests.

A human live test must begin by gracefully quitting the old build through its menu, then running the
intended signed Debug product from Xcode. Xcode Stop is a hard termination and does not test graceful
window restoration. Use **Quit WindowRanger** when validating quit recovery.

When a pull request still needs signed-app or multi-display testing, say so plainly. Passing unit
tests is not evidence that live Accessibility behaviour, packaging, notarization, or distribution
has been validated.

While the repository is private, automatic hosted jobs are skipped to preserve the GitHub Free
allowance; `workflow_dispatch` remains an explicit, potentially billable maintainer action. Local
pre-push verification is the default gate in that phase. Once the repository is public, standard
hosted runners become the independent gate automatically: pull requests targeting `develop` or
`main` run generation, syntax, isolation, and tests, while pushes to `main`, `develop`, `release/**`,
or `hotfix/**` additionally run static analysis, an unsigned Release build, and Stable/Beta DMG
smoke packaging. Topic-branch pushes do not duplicate the pull-request run. Hosted jobs deliberately
have no Apple signing or notarization secrets. Maintainer-only distribution uses the
[first-release runbook](docs/first-github-release.md), not the daily installer.

## Pull request workflow

1. Fork the repository and create a short-lived topic branch from `develop`. Use
   `fix/<wr-id>-<topic>`, `feature/<wr-id>-<topic>`, `docs/<wr-id>-<topic>`, or
   `chore/<wr-id>-<topic>` in lowercase kebab-case; omit the work-item ID when none exists.
2. Make the smallest coherent change and add or update tests and documentation.
3. Run the isolation check and the relevant tests.
4. Open a pull request using the repository template. Link the issue when one exists.
5. Describe user-visible behaviour, risk, automated evidence, and any live validation still needed.
6. Address review feedback with additional commits; maintainers may squash when merging.

Ordinary pull requests target `develop`. Only reviewed `release/*` and `hotfix/*` promotion work
targets `main`; contributors must not retarget feature work to Stable to bypass the release flow.

Before requesting review, confirm that the change:

- contains no credentials, private diagnostics, machine-specific paths, DerivedData, `.build`, app
  bundles, or accidental screenshots;
- preserves the non-hosted test boundary and the safety invariants in `ARCHITECTURE.md`;
- includes tests proportionate to the risk;
- updates README, architecture, privacy, or release documentation when those claims changed;
- leaves unrelated formatting or generated-project churn out of the diff.

Contributors are responsible for understanding and reviewing everything they submit, including code
produced with automated or AI-assisted tools.

## Licensing

By submitting a contribution, you agree that it may be distributed under the repository's
[MIT License](LICENSE). No contributor licence agreement is currently required.
