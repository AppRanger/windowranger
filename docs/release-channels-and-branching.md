# Release channels and branching

> **Decision record:** This defines the intended release and Git workflow. It does not authorise
> publishing, signing, notarisation, distribution, branch creation, repository-setting changes, or
> Sparkle implementation. Those remain gated by the pre-release checklist.

WindowRanger will use three release channels—Stable, Beta, and Dev—on a lightweight Gitflow-style
branch model. Stable and Beta will use Sparkle later. Dev is a rolling development-build stream and
will not be an auto-update channel.

The initial pipeline is intentionally local-first: GitHub Actions verifies clean generation, tests,
analysis, an unsigned Release build, and Stable/Beta DMG packaging; the maintainer's Mac owns
Developer ID signing, notarization, stapling, and release packaging. See
[First GitHub release](first-github-release.md). After the process is proven, the credentialed
portion may move to a protected CI environment.

## Channel contract

| Channel | Source | Version example | Audience | Delivery and support |
| --- | --- | --- | --- | --- |
| Stable | `main` | `1.2.0` / tag `v1.2.0` | Normal users | Signed, notarised release; default Sparkle channel later; latest stable supported. |
| Beta | `release/1.2.0` | `1.2.0-beta.2` / tag `v1.2.0-beta.2` | Opt-in testers | Signed, notarised prerelease; Sparkle `beta` channel later; latest beta supported best effort. |
| Dev | `develop` | `1.3.0-dev.184+abc1234` | Contributors and internal testing | Rolling CI/local artifact; no Sparkle, release promise, notarisation promise, or support window. |

Before `1.0.0`, the same structure applies under the `0.y.z` initial-development series. A version
number describes product compatibility; it does not by itself prove that a build passed the release
gates.

All publicly distributed Stable and Beta builds retain the canonical
`com.windowranger.WindowRanger` bundle identifier and Developer ID application identity. Do not
create channel-specific public identifiers: doing so would create parallel Accessibility clients
and make update promotion unreliable. A future development-only Xcode identity is a separate local
tooling decision; it would not be a public Dev release promise and must be documented in the daily
development workflow before implementation.

Build configuration does not determine the release channel. A local Release-configuration build
from `develop` remains Dev; only provenance, completed gates, and promotion through the flow below
make a build Beta or Stable. The separate
[daily development workflow](daily-development-workflow.md) controls which local copy is running.

## Long-lived branches

### `main`

`main` is the stable source of truth. Every commit on `main` must correspond to released or
release-ready stable code. Stable tags are created from `main`; ordinary feature work never targets
it directly.

### `develop`

`develop` is the integration branch for the next release. Feature, fix, documentation, maintenance,
and ordinary agent branches start from and merge into `develop`. A green `develop` commit may produce
a Dev artifact, but it is not a Beta or Stable release.

The GitHub repository uses `develop` as its default branch so new pull requests target the normal
integration path. This does not change `main`'s role as the Stable source of truth.

## Short-lived branches

| Pattern | Starts from | Merges into | Purpose |
| --- | --- | --- | --- |
| `feature/<wr-id>-<topic>` | `develop` | `develop` | User-facing product work. |
| `fix/<wr-id>-<topic>` | `develop` | `develop` | Ordinary defects for the next release. |
| `docs/<wr-id>-<topic>` | `develop` | `develop` | Documentation-only changes. |
| `chore/<wr-id>-<topic>` | `develop` | `develop` | Tooling and repository maintenance. |
| `codex/<wr-id>-<topic>` | Appropriate base, normally `develop` | Appropriate integration branch | Agent-authored work. |
| `release/<version>` | `develop` | `main`, then back to `develop` | Beta stabilisation and stable promotion. |
| `hotfix/<version>` | `main` | `main`, then back to `develop` and any active release branch | Urgent stable correction. |

Use lowercase kebab-case after the prefix. Omit the work-item ID only when no `WR-###` item exists.
Release and hotfix versions omit the leading `v`; tags include it.

## Release flow

### Dev

1. Merge reviewed topic branches into `develop`.
2. Run the non-hosted test suite and any proportionate checks.
3. CI may retain a rolling Dev artifact identified by the intended next version, a monotonically
   increasing build number, and the short commit hash.
4. Do not create permanent Dev tags or GitHub Releases for ordinary integration commits.

Dev artifacts must be visibly identified as development builds and must not be presented as signed,
notarised, supported, or safe for ordinary users unless those properties were actually verified.

### Beta

1. Cut `release/X.Y.Z` from a reviewed `develop` checkpoint.
2. Freeze feature scope. Allow only fixes, tests, release documentation, versioning, and packaging
   work required for `X.Y.Z`.
3. Publish sequential prerelease tags from that branch: `vX.Y.Z-beta.1`,
   `vX.Y.Z-beta.2`, and so on.
4. Apply each release-branch correction back to `develop` promptly so the next release cannot
   regress.
5. Mark GitHub Beta releases as prereleases when GitHub Releases becomes part of distribution.

### Stable

1. Complete every applicable release gate and the signed-app manual regression boundary.
2. Merge `release/X.Y.Z` into `main` without changing the already-reviewed release contents.
3. Create the annotated stable tag `vX.Y.Z` from `main` and publish the immutable release artifacts.
4. Merge `main` back into `develop`, then delete the completed release branch.

No released tag or artifact may be replaced. A correction receives a new patch version.

### Hotfix

1. Cut `hotfix/X.Y.Z` from the affected stable `main` commit.
2. Make the smallest safe correction and run the full release checks proportionate to its risk.
3. Merge into `main`, create `vX.Y.Z`, and publish a new immutable stable release.
4. Merge the result back into `develop` and any active `release/*` branch.

## Version and build numbers

- Public versions use `MAJOR.MINOR.PATCH`.
- Beta prereleases use `MAJOR.MINOR.PATCH-beta.N` with `N` starting at 1 for each version.
- Dev artifacts use `MAJOR.MINOR.PATCH-dev.BUILD+SHA` in artifact metadata and diagnostics; they are
  not permanent release tags.
- `CFBundleVersion` / `CURRENT_PROJECT_VERSION` must be a monotonically increasing build number
  across every Stable and Beta artifact. Sparkle compares this build number when deciding whether an
  update is newer.
- The final Stable build number for `X.Y.Z` must be greater than every `X.Y.Z-beta.N` build number.
- `CFBundleShortVersionString` / `MARKETING_VERSION` remains compatible with Apple's bundle-version
  requirements. Human-facing prerelease labels can be supplied in release metadata and Sparkle's
  short-version string rather than inventing an invalid bundle version.

The distribution script is the enforcement boundary for version syntax, branch/channel agreement,
and the build number embedded in an artifact. The maintainer still assigns the next monotonically
increasing build number; that decision must be recorded as release work and must not be made casually
on topic branches. Sparkle implementation must add an authoritative allocation/check before more
than one builder can produce public artifacts.

## Future Sparkle behaviour

Sparkle is not implemented yet. When it is added:

- use one signed appcast rather than independent stable and beta products;
- publish Stable updates on Sparkle's default channel;
- publish Beta updates with `<sparkle:channel>beta</sparkle:channel>`;
- make Beta an explicit user choice and allow the updater's `beta` channel only while opted in;
- remember that Sparkle channel clients always see the default channel too, so a Beta user may move
  forward to a newer Stable release;
- keep Dev builds outside the appcast and update them manually or through CI artifacts;
- sign update archives and the appcast, host release notes, and verify upgrade and rollback paths
  before enabling automatic checks.

Opting out of Beta is not necessarily an immediate downgrade. If the installed Beta has a higher
build number than the latest Stable release, the user remains on that build until a newer Stable is
published or they deliberately install an older Stable build using a documented manual process.

## Repository protections and current GitHub settings

The repository currently uses `develop` as its default branch. Actions are enabled with a read-only
default workflow token, and the CI workflow supplies explicit `contents: read` permission. The
private repository's current GitHub plan does not expose branch protection or rulesets; GitHub's API
requires either GitHub Pro while private or a public repository for these controls.

Before accepting public contributions—or immediately after the explicit visibility change if the
private plan prevents advance configuration—configure rulesets for `main` and `develop`:

- require pull requests and passing required checks;
- require the branch to be current before merge;
- block force pushes and deletion;
- require CODEOWNERS review for repository policy and release-sensitive files;
- restrict stable tags matching `v*` to release maintainers;
- keep release publication and signing permissions separate from ordinary write access.

Use the required check emitted by `.github/workflows/ci.yml`, retain read-only workflow permissions,
enable automatic deletion of merged topic branches, and review whether merge commits remain useful
alongside squash/rebase. Record the applied rules in this section rather than assuming that a YAML
file can enforce repository settings. Publishing and the visibility change remain separate manual
approval gates.
