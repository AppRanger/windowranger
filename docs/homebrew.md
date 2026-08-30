# Homebrew distribution

WindowRanger's initial Homebrew package is a Stable-only Cask for the same signed, notarized,
immutable DMG offered as the direct download. Beta and Dev builds are deliberately excluded.
Creating a Cask file, publishing an AppRanger tap, and submitting to `homebrew/cask` are separate
checkpoints; none authorizes another.

## Published route

The main `homebrew/cask` repository applies notability requirements to new submissions. Until
WindowRanger meets the current threshold, the reviewed Stable Cask is published through the public
[`AppRanger/homebrew-tap`](https://github.com/AppRanger/homebrew-tap) repository. Install it with:

```sh
brew install --cask appranger/tap/windowranger
```

After `brew tap appranger/tap`, the shorter `brew install --cask windowranger` also works. Once the
app is eligible and accepted upstream, the unqualified command works without the AppRanger tap.

The published 1.0.0 Cask was generated from the exact public release DMG. Homebrew 6 style and
strict online tap audit passed after fetching the Cask from the public repository, and `brew info`
resolved version 1.0.0 with the intended application artifact. On 30 August 2026, the public Cask
also passed install, reinstall, ordinary uninstall, explicit `--zap`, state restoration, and final
reinstall on an Apple Silicon Mac running macOS 27. The later-version upgrade paths, Intel,
Settings-managed PATH interaction, and macOS privacy-permission checks below remain live
validation.

## Generate the exact Cask

After the Stable GitHub release is public, immutable, and backed by the exact local distribution
directory, generate the Cask with:

```sh
./scripts/generate-homebrew-cask.sh \
  --version X.Y.Z \
  --release-directory .build/releases/X.Y.Z \
  --verify-public \
  --output .build/homebrew/windowranger.rb
```

The generator rejects prerelease versions, malformed checksums, draft or prerelease GitHub
releases, mutable releases, and any public DMG that differs from the locally verified artifact. It
will not overwrite an existing output unless `--replace` is explicit. It does not create a tap,
push, submit, install, or publish anything.

Run the deterministic construction checks with:

```sh
./scripts/verify-homebrew-cask-workflow.sh
```

Then copy the generated `windowranger.rb` into the selected tap and run the tap's current required
`brew style`, `brew audit`, installation, upgrade, ordinary uninstall, and `--zap` validation before
publication. Audit the AppRanger tap with `--strict --online`; `--new` applies the upstream
`homebrew/cask` notability gate and is expected to reject the separately documented tap route until
WindowRanger becomes eligible upstream.

## Sparkle coexistence

The Cask declares `auto_updates true` because Stable WindowRanger builds retain their signed Sparkle
updater. Homebrew can compare the installed app bundle's readable version with the versioned Cask,
so an app already updated by Sparkle is not silently downgraded by an ordinary Homebrew upgrade.
Either updater installs the same Developer ID identity at `/Applications/WindowRanger.app`.

Homebrew should never use a Beta asset for the unversioned Cask. A Stable client may opt into Beta
inside WindowRanger, but that is an app-local choice and does not change the Cask's Stable source.

## Uninstall and `--zap`

Ordinary `brew uninstall --cask windowranger` quits and removes the app but preserves user
preferences, profiles, cached recovery state, and diagnostics. This matches ordinary Finder
uninstall behavior and avoids erasing configuration unexpectedly.

Explicit `--zap` additionally removes WindowRanger's current and legacy local preference, cache,
HTTP storage, log, and saved-state paths declared in the Cask. It deliberately does not remove:

- profile export files or any other documents created by the user;
- the user's private iCloud key-value copy;
- `~/.local/bin/windowranger` or managed shell-startup text, because those paths may have been
  changed or taken over since the in-app **Add to PATH** action ran.

Before uninstalling, a user who enabled **Add to PATH** should use **Remove from PATH** in General
Settings. A later dedicated, ownership-checking uninstall helper may automate that without risking
another tool's link or deleting a user's shell file.

## Remaining Stable live-validation boundary

Before treating Homebrew distribution as fully live-validated:

1. Generate from the exact public Stable DMG with `--verify-public`.
2. Run the selected tap's current style and online audit checks.
3. Complete the already-passing Apple Silicon install lifecycle on an Intel-supported environment
   without first placing another WindowRanger copy in `/Applications`.
4. Launch and verify the app version, bundle identifier, Developer ID signature, notarization,
   embedded universal CLI, and Settings-managed PATH action.
5. Upgrade through Homebrew and Sparkle in both orders and confirm neither path downgrades the app.
6. Retain the passing evidence that ordinary uninstall preserves configuration, while `--zap`
   removes exactly its declared local scope.
7. Retest Accessibility and Screen Recording permission behavior. Matching bundle identity and
   signature are necessary but do not prove macOS will preserve either permission.
