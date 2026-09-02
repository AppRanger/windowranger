# Sparkle updates

WindowRanger uses Sparkle 2.8.1 for distributable Stable and Beta builds. Rolling Dev builds remain
outside the update feed and do not construct a Sparkle updater, even when this Mac has saved update
preferences.

## Runtime contract

- Stable is the default channel. A Stable client never allows Beta entries.
- Beta is an explicit local choice. It adds Sparkle's `beta` channel while retaining eligibility for
  newer Stable entries.
- A newly installed Beta artifact begins opted in to Beta. A saved opt-out wins on later launches,
  including while that Beta artifact remains installed.
- Returning to Stable never silently downgrades a newer Beta build. The client waits for a Stable
  entry with a higher `CFBundleVersion`.
- Automatic checks and automatic downloads are local, off by default, and independent of profiles
  and iCloud sync.
- A manual check disables duplicate requests while the check is running, queues the request while
  Sparkle is completing startup or background work, and keeps its progress or terminal result
  visible in Settings. Sparkle retains ownership of the standard checking, update, up-to-date, and
  failure presentation. WindowRanger observes Sparkle's current update-cycle completion callback so
  no-update and failure outcomes always clear the pending state.
- `SUVerifyUpdateBeforeExtraction` remains enabled. Every update ZIP must carry the EdDSA signature
  produced by Sparkle's official `generate_appcast` tool.

The build embeds `WindowRangerUpdateChannel`, `SUFeedURL`, and `SUPublicEDKey`. A distributable build
fails release preflight without an HTTPS feed URL and the public EdDSA key. A Dev or malformed build
shows the reason Updates are unavailable and cannot accidentally contact the feed.

## One-time release setup

The maintainer creates the EdDSA key with the `generate_keys` tool shipped in the pinned Sparkle
package using the account `dev.appranger.WindowRanger.updates`. This is a credential operation: keep the private key in the maintainer Keychain or approved
secret storage, record its recovery procedure privately, and commit only the public key if the
release process later chooses that approach. Key creation and live feed publication require their
own explicit release approval.

The appcast is hosted at `https://windowranger.com/appcast.xml`. Its signed update ZIPs and deltas
use the stable `https://windowranger.com/updates/` prefix. The first uploaded ZIP must be byte-for-byte
identical to the checksum-verified immutable GitHub release asset; retaining it in the feed history
also lets Sparkle generate later deltas without rewriting older enclosure URLs.

## Build and feed flow

First reserve the next public build number in `config/release-builds.tsv`. Append an `allocated`
row on `develop`, commit it, and only then create or promote the release branch. The ledger is the
repository authority: released and superseded numbers stay in place permanently, and the
distribution preflight accepts only the single latest active allocation. Mark that row `published`
after the exact immutable GitHub release is public, or `superseded` when abandoning it, before
appending another allocation. Appcast generation then requires the latest `published` pair and
fetches the ledger from central `develop` again before touching the local feed, preventing an older
release from replacing a newer published candidate. It also fetches the live appcast again and
rejects any build that is not newer than its published maximum. Feed deployment remains a separate
checkpoint and is not represented by the ledger state.

Set the public key without exposing the private key:

```sh
export WINDOWRANGER_SPARKLE_PUBLIC_ED_KEY='PUBLIC_KEY_FROM_GENERATE_KEYS'
```

Run the ordinary distribution command. Add `--initial-update-feed` only for the first
update-enabled artifact and only while the public endpoint returns an authoritative HTTP 404 or
410. The flag is rejected after an appcast exists. Subsequent builds download the current appcast
and reject a build number that is not strictly greater than every published `sparkle:version`.

After the exact ZIP is notarized, tagged, uploaded, verified, published as a public GitHub
release, and approved for the separate feed checkpoint, first run the uncredentialed preflight:

```sh
./scripts/generate-update-appcast.sh \
  --version VERSION \
  --feed-directory /absolute/path/to/private-feed-workdir \
  --sparkle-bin /absolute/path/to/Sparkle/bin \
  --release-notes docs/releases/vVERSION.md \
  --preflight
```

This verifies the exact latest `published` ledger entry, the public GitHub checksum, the local
archive, and the current live appcast without asking for the private update key. Once it passes,
run the same command without `--preflight` to update the local feed working directory with Sparkle's
package tools:

```sh
./scripts/generate-update-appcast.sh \
  --version VERSION \
  --feed-directory /absolute/path/to/private-feed-workdir \
  --sparkle-bin /absolute/path/to/Sparkle/bin \
  --release-notes docs/releases/vVERSION.md
```

The script verifies the local release checksum and the checksum attached to the public GitHub
release, stages a complete copy of the feed, adds the notarized ZIP and release notes, signs the new
enclosure using the existing Keychain EdDSA key, adds
`<sparkle:channel>beta</sparkle:channel>` for Beta versions, and validates the expected build,
archive, channel and every retained enclosure before replacing the original local feed. A signing,
generation or validation failure leaves the original feed untouched. It never creates keys,
uploads files, deploys the website, publishes a GitHub release, or changes shared infrastructure.
The validator accepts Sparkle's recommended top-level `<sparkle:version>` element and the legacy
enclosure attribute so retained feed history remains compatible across generator versions.

The separately reviewed website change publishes `appcast.xml` plus every ZIP and delta referenced
by that feed beneath `/updates/`. Keep the local feed history retained so Sparkle can generate and
validate later deltas. The script validates every enclosure against the version-independent public
prefix and a matching local artifact; a release-tag-specific prefix is forbidden because Sparkle
rewrites preserved enclosure URLs whenever the appcast is regenerated.

The central ledger check serializes release preparation, but the final website deployment still
requires the normal single-maintainer review: deploy exactly the feed directory just generated,
verify the live appcast and every enclosure. The ledger entry is already `published` because the
public GitHub release is a prerequisite for feed generation; do not reinterpret it as proof that
the separate appcast deployment succeeded.

## Activation gates

Before publishing the first appcast or enabling automatic checks by default, test with signed,
notarized packaged apps on a clean user account or second supported Mac:

1. an older Stable finds and installs a newer Stable;
2. Stable excludes a newer Beta;
3. opted-in Beta sees eligible Beta and newer Stable entries;
4. opting out on a newer Beta waits rather than downgrading;
5. signature tampering and wrong keys fail closed;
6. cancellation, network failure, malformed feed, relaunch, and install failure remain recoverable;
7. release notes render correctly and a documented manual replacement remains available;
8. the exact resulting app preserves the expected bundle identity and Accessibility guidance.

Passing unit tests or compiling Sparkle into the app does not satisfy these packaged-app gates.
