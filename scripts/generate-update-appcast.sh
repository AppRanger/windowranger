#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
script_name="${0:t}"
release_root="${WINDOWRANGER_RELEASE_ROOT:-$repository_root/.build/releases}"
version=""
feed_directory=""
sparkle_bin="${WINDOWRANGER_SPARKLE_BIN:-}"
release_notes=""
key_account="${WINDOWRANGER_SPARKLE_KEY_ACCOUNT:-ed25519}"
published_archive_prefix="https://windowranger.com/updates/"
published_appcast_url="https://windowranger.com/appcast.xml"
authoritative_registry_url="https://raw.githubusercontent.com/AppRanger/windowranger/develop/config/release-builds.tsv"
test_release_inputs_enabled=false

usage() {
    print "Usage: $script_name --version VERSION --feed-directory DIR --sparkle-bin DIR --release-notes FILE [--key-account ACCOUNT]"
    print ""
    print "Adds an already notarized WindowRanger ZIP to a local signed Sparkle appcast."
    print "The command never creates keys, uploads files, deploys the website, or publishes a release."
    print ""
    print "Environment overrides:"
    print "  WINDOWRANGER_RELEASE_ROOT  Artifact root (default: .build/releases)"
    print "  WINDOWRANGER_SPARKLE_BIN  Directory containing Sparkle's generate_appcast tool"
    print "  WINDOWRANGER_SPARKLE_KEY_ACCOUNT  Keychain account for the existing EdDSA private key"
}

while (( $# > 0 )); do
    case "$1" in
        --version)
            (( $# >= 2 )) || { print -u2 "--version requires a value"; exit 2; }
            version="$2"
            shift
            ;;
        --feed-directory)
            (( $# >= 2 )) || { print -u2 "--feed-directory requires a value"; exit 2; }
            feed_directory="$2"
            shift
            ;;
        --sparkle-bin)
            (( $# >= 2 )) || { print -u2 "--sparkle-bin requires a value"; exit 2; }
            sparkle_bin="$2"
            shift
            ;;
        --release-notes)
            (( $# >= 2 )) || { print -u2 "--release-notes requires a value"; exit 2; }
            release_notes="$2"
            shift
            ;;
        --key-account)
            (( $# >= 2 )) || { print -u2 "--key-account requires a value"; exit 2; }
            key_account="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print -u2 "Unknown option: $1"
            usage >&2
            exit 2
            ;;
    esac
    shift
done

[[ -n "$version" ]] || { print -u2 "Missing --version"; exit 2; }
[[ -n "$feed_directory" ]] || { print -u2 "Missing --feed-directory"; exit 2; }
[[ -n "$sparkle_bin" ]] || { print -u2 "Missing --sparkle-bin or WINDOWRANGER_SPARKLE_BIN"; exit 2; }
[[ -n "$release_notes" ]] || { print -u2 "Missing --release-notes"; exit 2; }
print -r -- "$version" | /usr/bin/grep -Eq \
    '^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[1-9][0-9]*)?$' || {
    print -u2 "Version must be X.Y.Z or X.Y.Z-beta.N: $version"
    exit 2
}

feed_directory="${feed_directory:A}"
sparkle_bin="${sparkle_bin:A}"
release_notes="${release_notes:A}"
feed_parent="${feed_directory:h}"
feed_name="${feed_directory:t}"
generate_appcast="$sparkle_bin/generate_appcast"
release_directory="$release_root/$version"
archive_name="WindowRanger-$version.zip"
archive="$release_directory/$archive_name"
manifest="$release_directory/WindowRanger-$version.release.txt"
checksum="$archive.sha256"

if [[ "${WINDOWRANGER_TEST_RELEASE_INPUTS:-0}" == 1 ]]; then
    parent_command="$(/bin/ps -p "$PPID" -o command= 2>/dev/null || true)"
    [[ "$release_root" == "${TMPDIR:-/tmp}/windowranger-sparkle-feed-test."*/releases &&
       "$parent_command" == *scripts/verify-sparkle-feed-workflow.sh* ]] || {
        print -u2 "Test release inputs are available only to the isolated workflow verifier"
        exit 1
    }
    test_release_inputs_enabled=true
fi

[[ -x "$generate_appcast" ]] || { print -u2 "Sparkle tool not executable: $generate_appcast"; exit 1; }
[[ -d "$feed_directory" ]] || { print -u2 "Feed directory does not exist: $feed_directory"; exit 1; }
[[ -d "$feed_parent" && -n "$feed_name" && "$feed_name" != . && "$feed_name" != .. ]] || {
    print -u2 "Feed directory must have a safe existing parent: $feed_directory"
    exit 1
}
[[ -f "$archive" ]] || { print -u2 "Release archive not found: $archive"; exit 1; }
[[ -f "$manifest" ]] || { print -u2 "Release manifest not found: $manifest"; exit 1; }
[[ -f "$checksum" ]] || { print -u2 "Release checksum not found: $checksum"; exit 1; }
[[ -f "$release_notes" ]] || { print -u2 "Release notes not found: $release_notes"; exit 1; }

manifest_version="$(/usr/bin/awk -F= '$1 == "version" { print $2 }' "$manifest")"
build_number="$(/usr/bin/awk -F= '$1 == "build_number" { print $2 }' "$manifest")"
[[ "$manifest_version" == "$version" ]] || { print -u2 "Manifest version does not match $version"; exit 1; }
print -r -- "$build_number" | /usr/bin/grep -Eq '^[1-9][0-9]*$' || {
    print -u2 "Manifest has no valid build number"
    exit 1
}
(cd "$release_directory" && /usr/bin/shasum -a 256 -c "${checksum:t}")

# Compare again with the public feed immediately before local generation. This is deliberately
# repeated after distribution preflight because release preparation can take long enough for a
# different artifact to be published.
public_appcast_snapshot="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/windowranger-public-appcast.XXXXXX")"
if [[ "$test_release_inputs_enabled" == true ]]; then
    if [[ -f "$feed_directory/appcast.xml" ]]; then
        /bin/cp "$feed_directory/appcast.xml" "$public_appcast_snapshot"
        public_appcast_http_code=200
    else
        public_appcast_http_code=404
    fi
elif ! public_appcast_http_code="$(/usr/bin/curl --silent --show-error --location --max-time 20 \
    --header 'Cache-Control: no-cache' --write-out '%{http_code}' \
    "$published_appcast_url?release_check=$(/bin/date +%s)" \
    --output "$public_appcast_snapshot" 2>/dev/null)"; then
    public_appcast_http_code=000
fi
if [[ "$public_appcast_http_code" == 200 ]]; then
    latest_published_build="$(
        /usr/bin/grep -Eo 'sparkle:version="[1-9][0-9]*"' "$public_appcast_snapshot" |
            /usr/bin/sed -E 's/.*="([0-9]+)"/\1/' |
            /usr/bin/sort -n |
            /usr/bin/tail -1
    )"
    if [[ -z "$latest_published_build" ]]; then
        /bin/rm -f -- "$public_appcast_snapshot"
        print -u2 "The public Sparkle appcast contains no numeric build history"
        exit 1
    elif (( build_number <= latest_published_build )); then
        /bin/rm -f -- "$public_appcast_snapshot"
        print -u2 "Build $build_number cannot follow public appcast build $latest_published_build"
        exit 1
    fi
elif [[ "$public_appcast_http_code" != 404 && "$public_appcast_http_code" != 410 ]]; then
    /bin/rm -f -- "$public_appcast_snapshot"
    print -u2 "Could not verify the current public appcast (HTTP $public_appcast_http_code)"
    exit 1
fi
/bin/rm -f -- "$public_appcast_snapshot"

# Recheck the central develop ledger at the last local step before website promotion. Release
# branches may have stale ledger snapshots; only one allocation may be active on develop, so an
# older branch cannot generate a feed after a newer number has been reserved.
registry_snapshot="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/windowranger-release-builds.XXXXXX")"
if [[ "$test_release_inputs_enabled" == true ]]; then
    /bin/cp "$release_root/release-builds.tsv" "$registry_snapshot"
elif ! /usr/bin/curl --fail --silent --show-error --location --max-time 20 \
    --header 'Cache-Control: no-cache' \
    "$authoritative_registry_url?release_check=$(/bin/date +%s)" --output "$registry_snapshot"; then
    /bin/rm -f -- "$registry_snapshot"
    print -u2 "Could not download the authoritative release build ledger from develop"
    exit 1
fi
if ! registry_result="$(WINDOWRANGER_RELEASE_BUILD_REGISTRY="$registry_snapshot" \
    "$repository_root/scripts/verify-release-build-registry.sh" \
    --version "$version" --build-number "$build_number" 2>&1)"; then
    /bin/rm -f -- "$registry_snapshot"
    print -u2 "$registry_result"
    print -u2 "Resolve or publish the central allocation before generating this appcast"
    exit 1
fi
/bin/rm -f -- "$registry_snapshot"

staging_directory="$(/usr/bin/mktemp -d "$feed_parent/.${feed_name}.staging.XXXXXX")"
backup_directory="$feed_parent/.${feed_name}.backup.$$"

cleanup() {
    if [[ -n "${staging_directory:-}" && "$staging_directory" == "$feed_parent/.${feed_name}.staging."* && -d "$staging_directory" ]]; then
        /bin/rm -R -- "$staging_directory"
    fi
    if [[ -n "${backup_directory:-}" && "$backup_directory" == "$feed_parent/.${feed_name}.backup."* && -d "$backup_directory" && ! -e "$feed_directory" ]]; then
        /bin/mv -- "$backup_directory" "$feed_directory"
    fi
}
trap cleanup EXIT INT TERM

# Work on a same-filesystem copy. A signing, generation, or validation failure leaves the caller's
# feed byte-for-byte untouched.
/usr/bin/ditto "$feed_directory" "$staging_directory"
/bin/cp -p "$archive" "$staging_directory/$archive_name"
notes_extension="${release_notes:e:l}"
if [[ "$notes_extension" != html && "$notes_extension" != txt ]]; then
    notes_extension="txt"
fi
/bin/cp -p "$release_notes" "$staging_directory/WindowRanger-$version.$notes_extension"

typeset -a appcast_arguments
appcast_arguments=(
    --account "$key_account"
    # This prefix must remain version-independent. generate_appcast rewrites preserved enclosure
    # URLs on later runs, so a release-tag-specific prefix would silently break every older item.
    --download-url-prefix "$published_archive_prefix"
    --link "https://windowranger.com/"
    --versions "$build_number"
    --maximum-versions 0
    --embed-release-notes
    -o "$staging_directory/appcast.xml"
)
if [[ "$version" == *-beta.* ]]; then
    appcast_arguments+=(--channel beta)
fi

"$generate_appcast" "${appcast_arguments[@]}" "$staging_directory"

appcast="$staging_directory/appcast.xml"
[[ -f "$appcast" ]] || { print -u2 "Sparkle did not generate $appcast"; exit 1; }
/usr/bin/grep -Fq "sparkle:version=\"$build_number\"" "$appcast" || {
    print -u2 "Generated appcast does not contain build $build_number"
    exit 1
}
/usr/bin/grep -Fq "$archive_name" "$appcast" || {
    print -u2 "Generated appcast does not contain $archive_name"
    exit 1
}
if [[ "$version" == *-beta.* ]]; then
    /usr/bin/grep -Fq '<sparkle:channel>beta</sparkle:channel>' "$appcast" || {
        print -u2 "Generated Beta entry is missing the Sparkle beta channel"
        exit 1
    }
fi

typeset -a enclosure_urls
enclosure_urls=("${(@f)$(
    /usr/bin/grep -Eo 'url="[^"]+"' "$appcast" |
        /usr/bin/sed -E 's/^url="([^"]+)"$/\1/'
)}")
(( ${#enclosure_urls} > 0 )) || {
    print -u2 "Generated appcast contains no enclosure URLs"
    exit 1
}
for enclosure_url in "${enclosure_urls[@]}"; do
    [[ "$enclosure_url" == "$published_archive_prefix"* ]] || {
        print -u2 "Appcast enclosure does not use the stable archive prefix: $enclosure_url"
        exit 1
    }
    enclosure_name="${enclosure_url#$published_archive_prefix}"
    [[ -n "$enclosure_name" && "$enclosure_name" != */* && -f "$staging_directory/$enclosure_name" ]] || {
        print -u2 "Appcast enclosure has no matching local feed artifact: $enclosure_url"
        exit 1
    }
done

# Promote the validated directory as one unit. If the second rename fails, cleanup restores the
# original directory. The live website remains a separately approved publication step.
[[ ! -e "$backup_directory" ]] || { print -u2 "Feed backup path already exists: $backup_directory"; exit 1; }
/bin/mv -- "$feed_directory" "$backup_directory"
if ! /bin/mv -- "$staging_directory" "$feed_directory"; then
    /bin/mv -- "$backup_directory" "$feed_directory"
    print -u2 "Could not promote the validated feed; the original was restored"
    exit 1
fi
staging_directory=""
/bin/rm -R -- "$backup_directory"
backup_directory=""
appcast="$feed_directory/appcast.xml"

print "Local Sparkle feed updated:"
print "  Appcast: $appcast"
print "  Version: $version"
print "  Build: $build_number"
print "  Channel: $([[ "$version" == *-beta.* ]] && print beta || print stable)"
print ""
print "Next: review this diff and test the signed update from an older packaged build. The separately approved website change must publish the appcast and every referenced archive/delta beneath /updates/."
