# First GitHub release

WindowRanger's first public binary is `v0.1.0-beta.1`, not a Stable release. The product remains
explicitly pre-release and several live, accessibility, privacy, and packaging gates remain open.

As of 10 August 2026, that exact Beta is Developer ID-signed, notarized, stapled, packaged, tested by
the maintainer, and published as a
[GitHub prerelease](https://github.com/AppRanger/windowranger/releases/tag/v0.1.0-beta.1). The tag
and artifacts remain at commit `04b5750b1fe3b183c1259d132a0a8e985f8b4e0e`.

This runbook uses a local-first release pipeline:

| Owner | Responsibility |
| --- | --- |
| Local verification | While private, run exact-commit non-hosted checks through the opt-in pre-push hook and run the full uncredentialed checkpoint explicitly at integration/release boundaries. |
| GitHub Actions | Once public—or on an explicit private manual dispatch—generate the project, verify test isolation, run tests and static analysis, compile an unsigned universal Release configuration, and smoke-test both DMG layouts. |
| Maintainer's Mac | Use the Developer ID private key, archive/export, notarize, staple, package, and verify the exact release app and DMG. |
| GitHub Releases | Hold the immutable tag, draft notes, notarized DMG and ZIP, SHA-256 checksums, and provenance manifest. |

The daily installer is not a distribution tool. It deliberately builds a local development copy and
may use Apple Development signing. `scripts/build-distribution.sh` is the only scripted path for a
public binary.

## Why the first release is local

The maintainer's Mac already has the Apple account and local Keychain boundary needed for signing.
Keeping the first Developer ID private key and notarization credentials off GitHub makes the initial
workflow easier to inspect and debug. After at least one release is reproduced successfully, the
credentialed job can move to a protected GitHub Actions environment with required approval and
least-privilege secrets.

CI never turns an unsigned build into a public download and never receives signing or notarization
credentials in the current design.

## One-time Apple setup

1. Confirm the Apple Developer Program team and Account Holder that will own WindowRanger releases.
   The configured team is `44NAD22AK6`; do not release until that ownership is intentional.
2. Create and install a **Developer ID Application** certificate and its private key. An Apple
   Development certificate is not a distribution identity.
3. Ensure the WindowRanger App ID supports the required iCloud key-value entitlement. The release
   export uses automatic signing with `-allowProvisioningUpdates`, so Xcode creates or refreshes the
   direct Developer ID provisioning profile instead of relying on a locally named profile.
4. Store notarization credentials explicitly in the file-based login Keychain under a profile name
   such as `WindowRanger`. Supplying the keychain path avoids `notarytool`'s default Data Protection
   Keychain and makes the release script use the same deterministic store. For Apple ID
   authentication, run this interactively and substitute your own values:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
   /usr/bin/xcrun notarytool store-credentials WindowRanger \
     --keychain "$HOME/Library/Keychains/login.keychain-db" \
     --apple-id YOUR_APPLE_ID \
     --team-id 44NAD22AK6 \
     --validate
   ```

   Omitting `--password` makes `notarytool` request the app-specific password through its secure
   interactive prompt instead of placing it in shell history.

Never place the certificate, private key, app-specific password, App Store Connect key, or exported
`.p12` file in the repository.

## One-time Git setup

For the first Beta, complete and record these repository steps:

1. Create `develop` from the accepted `main` checkpoint, push it, and make it the default branch.
2. Preserve the recorded proof of automatic push and pull-request events. While private, automatic
   hosted jobs now skip to protect the included allowance; they resume when public.
3. Configure required checks and protection for `main`, `develop`, and release tags when GitHub Pro
   or public visibility makes rulesets available.
4. Cut `release/0.1.0` from `develop` and allow only release fixes, documentation, versioning, and
   packaging changes on that branch.

The branches and exact Beta tag now exist. Protection remains a public-visibility/GitHub-plan gate,
and automatic CI events must be evidenced independently of the manually dispatched release run.

Do not create the release branch or tags from a dirty worktree.

## Build and notarize the first Beta

Use stable Xcode. This Mac currently has stable Xcode at `/Applications/Xcode.app`; do not use the
selected Xcode beta for a public build.

Create a dedicated clean worktree so unrelated development changes cannot enter the release:

```sh
release_worktree="$(mktemp -d /tmp/windowranger-release.XXXXXX)"
git fetch origin
git worktree add "$release_worktree" release/0.1.0
cd "$release_worktree"
```

From that clean `release/0.1.0` worktree:

```sh
export WINDOWRANGER_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

./scripts/install-dmg-tools.sh

./scripts/build-distribution.sh \
  --version 0.1.0-beta.1 \
  --build-number 1 \
  --notary-profile WindowRanger \
  --notary-keychain "$HOME/Library/Keychains/login.keychain-db" \
  --preflight

./scripts/build-distribution.sh \
  --version 0.1.0-beta.1 \
  --build-number 1 \
  --notary-profile WindowRanger \
  --notary-keychain "$HOME/Library/Keychains/login.keychain-db"
```

The build command:

1. refuses the wrong branch, a dirty worktree, Xcode beta, or a missing Developer ID identity;
2. generates the Xcode project and verifies the non-hosted test boundary;
3. runs the complete test suite and static analysis;
4. creates a universal Release archive with Hardened Runtime;
5. exports with Developer ID and rejects `get-task-allow`;
6. submits the app through `notarytool`, saves the accepted submission result and zero-issue log,
   staples the ticket, and validates it with `stapler` and Gatekeeper;
7. creates and Developer ID-signs the channel-specific DMG with the `/Applications` shortcut,
   saves its accepted notarization result and zero-issue log, staples its ticket, and verifies the
   disk image;
8. writes the final DMG, fallback ZIP, SHA-256 checksums, and provenance manifest beneath
   `.build/releases/0.1.0-beta.1/`.

Build number `1` is the first distribution build. Every later Beta or Stable artifact must use a
strictly larger integer.

## Test the exact artifact

Do not test a separate Xcode product and assume the release DMG is equivalent.

1. Open `WindowRanger-0.1.0-beta.1.dmg` on another supported Mac or a clean macOS user account.
2. Confirm the Beta construction artwork and instruction, then drag `WindowRanger.app` onto the
   `Applications` shortcut and launch it normally through Finder.
3. Verify Gatekeeper identifies the Developer ID publisher without an unidentified-developer
   override.
4. Complete the relevant manual regression, permission, multi-display, privacy, and recovery checks
   from `docs/release-checklist.md`.
5. Confirm the fallback ZIP contains the same signed and notarized app.
6. Confirm graceful quit and uninstall behaviour and capture only privacy-safe evidence.

Any source, build-setting, entitlement, signing, or packaged-content change after this test requires
a new build number and a newly notarized artifact. Documentation-only release-process improvements
may follow on `develop`, but they do not rewrite the immutable tag or claim to be inside its binary.

## Tag and create the draft release

Only after the exact artifact passes:

```sh
git tag -a v0.1.0-beta.1 -m "WindowRanger 0.1.0 Beta 1"
git push origin v0.1.0-beta.1

./scripts/verify-release-assets.sh \
  --version 0.1.0-beta.1 \
  --expected-commit "$(git rev-parse HEAD)"

./scripts/create-github-release.sh \
  --version 0.1.0-beta.1 \
  --notes-file docs/releases/v0.1.0-beta.1.md
```

Use [the release-notes template](release-notes-template.md) as the starting point. The command
requires the pushed tag to point to `HEAD`, attaches the DMG, fallback ZIP, both checksums, and the
manifest, marks a Beta as a prerelease, and creates a **draft**. Before upload it validates the local
checksums, manifest, version and commit. It then downloads the five attached assets and repeats the
same verification against the immutable tag. It cannot publish the release or make the repository
public.

To repeat the round-trip verification without changing an existing draft or published release:

```sh
./scripts/create-github-release.sh --version 0.1.0-beta.1 --verify-existing
```

For a later release, review the draft on GitHub and explicitly publish it only after every applicable
gate for that release is complete. GitHub's automatically generated source archives are not the
macOS app and must not be described as the install download.

## Repository visibility

The repository became public on 10 August 2026 after the history/privacy scan, licence review,
private security and conduct reporting paths, branch protection, and tag rules were verified.
Changing visibility and publishing a draft remain separate, explicit maintainer actions for any
future private release repository.

## Moving release signing to CI later

After the local process is proven, a protected GitHub Actions environment can import an encrypted
Developer ID `.p12`, install the provisioning profile, use an App Store Connect/notary credential,
run the same script, and create the draft release. Require manual environment approval and grant the
job only `contents: write` when it is actually publishing.

Do not add those secrets to the ordinary pull-request workflow. Pull requests, especially from
forks, must remain unable to access release credentials.
