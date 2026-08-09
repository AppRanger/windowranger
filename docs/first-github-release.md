# First GitHub release

WindowRanger's first public binary should be `v0.1.0-beta.1`, not a Stable release. The product is
still explicitly pre-release and several live, accessibility, privacy, identity, and packaging gates
remain open.

This runbook uses a local-first release pipeline:

| Owner | Responsibility |
| --- | --- |
| GitHub Actions | Generate the project, verify test isolation, run tests and static analysis, compile an unsigned universal Release configuration, and smoke-test both DMG layouts. |
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
3. Ensure the WindowRanger App ID and any Developer ID provisioning profile support the required
   iCloud key-value entitlement.
4. Store notarization credentials in the login Keychain under a profile name such as
   `WindowRanger`. For Apple ID authentication, run this interactively and substitute your own
   values:

   ```sh
   xcrun notarytool store-credentials WindowRanger \
     --apple-id YOUR_APPLE_ID \
     --team-id 44NAD22AK6 \
     --password YOUR_APP_SPECIFIC_PASSWORD
   ```

Never place the certificate, private key, app-specific password, App Store Connect key, or exported
`.p12` file in the repository.

## One-time Git setup

After the current repository changes are reviewed and committed:

1. Create `develop` from the accepted `main` checkpoint and push it.
2. Configure required CI checks and branch protection for `main` and `develop`.
3. Cut `release/0.1.0` from `develop`.
4. Allow only release fixes, documentation, versioning, and packaging changes on that branch.

Do not create the release branch or tags from a dirty worktree.

## Build and notarize the first Beta

Use stable Xcode. This Mac currently has stable Xcode at `/Applications/Xcode.app`; do not use the
selected Xcode beta for a public build.

From a clean `release/0.1.0` worktree:

```sh
export WINDOWRANGER_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

./scripts/install-dmg-tools.sh

./scripts/build-distribution.sh \
  --version 0.1.0-beta.1 \
  --build-number 1 \
  --notary-profile WindowRanger \
  --preflight

./scripts/build-distribution.sh \
  --version 0.1.0-beta.1 \
  --build-number 1 \
  --notary-profile WindowRanger
```

The build command:

1. refuses the wrong branch, a dirty worktree, Xcode beta, or a missing Developer ID identity;
2. generates the Xcode project and verifies the non-hosted test boundary;
3. runs the complete test suite and static analysis;
4. creates a universal Release archive with Hardened Runtime;
5. exports with Developer ID and rejects `get-task-allow`;
6. submits the app through `notarytool`, staples the ticket, and validates it with `stapler` and
   Gatekeeper;
7. creates the channel-specific DMG with the `/Applications` shortcut, submits the DMG to Apple,
   staples its ticket, and verifies the disk image;
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

Any change after this test requires a new build number and a newly notarized artifact.

## Tag and create the draft release

Only after the exact artifact passes:

```sh
git tag -a v0.1.0-beta.1 -m "WindowRanger 0.1.0 Beta 1"
git push origin v0.1.0-beta.1

./scripts/create-github-release.sh \
  --version 0.1.0-beta.1 \
  --notes-file /path/to/release-notes.md
```

Use [the release-notes template](release-notes-template.md) as the starting point. The command
requires the pushed tag to point to `HEAD`, attaches the DMG, fallback ZIP, both checksums, and the
manifest, marks a Beta as a prerelease, and creates a **draft**. It cannot publish the release or
make the repository public.

Review the draft on GitHub, download and checksum its attached asset once more, and then explicitly
publish it from GitHub. GitHub's automatically generated source archives are not the macOS app and
must not be described as the install download.

## Repository visibility

The repository is currently private, so a GitHub release is private too. Make the repository public
only after the history/privacy scan, licence review, security contact, conduct contact, and other
public-project gates are complete. Changing visibility and publishing the draft are separate,
explicit maintainer actions.

## Moving release signing to CI later

After the local process is proven, a protected GitHub Actions environment can import an encrypted
Developer ID `.p12`, install the provisioning profile, use an App Store Connect/notary credential,
run the same script, and create the draft release. Require manual environment approval and grant the
job only `contents: write` when it is actually publishing.

Do not add those secrets to the ordinary pull-request workflow. Pull requests, especially from
forks, must remain unable to access release credentials.
