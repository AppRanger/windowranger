#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/windowranger-homebrew-test.XXXXXX")"
release_directory="$test_root/releases/1.0.0"
public_root="$test_root/public"
output="$test_root/windowranger.rb"
dmg_name="WindowRanger-1.0.0.dmg"

cleanup() {
    [[ "$test_root" == "${TMPDIR:-/tmp}/windowranger-homebrew-test."* ]] || return
    /bin/rm -R -- "$test_root"
}
trap cleanup EXIT INT TERM

/bin/mkdir -p "$release_directory" "$public_root"
print 'fixture stable dmg' > "$release_directory/$dmg_name"
(cd "$release_directory" && /usr/bin/shasum -a 256 "$dmg_name" > "$dmg_name.sha256")

run_generator() {
    "$repository_root/scripts/generate-homebrew-cask.sh" \
        --version 1.0.0 \
        --release-directory "$release_directory" \
        --output "$output" \
        "$@" >/dev/null
}

run_generator
/usr/bin/ruby -c "$output" >/dev/null
expected_checksum="$(/usr/bin/shasum -a 256 "$release_directory/$dmg_name" | /usr/bin/awk '{ print $1 }')"
/usr/bin/grep -Fq "version \"1.0.0\"" "$output"
/usr/bin/grep -Fq "sha256 \"$expected_checksum\"" "$output"
/usr/bin/grep -Fq 'auto_updates true' "$output"
/usr/bin/grep -Fq 'depends_on macos: :sonoma' "$output"
/usr/bin/grep -Fq 'uninstall quit: "dev.appranger.WindowRanger"' "$output"
if /usr/bin/grep -Fq 'verified:' "$output"; then
    print -u2 "Generator emitted Homebrew's deprecated verified URL parameter"
    exit 1
fi

before_existing="$(/usr/bin/shasum -a 256 "$output" | /usr/bin/awk '{ print $1 }')"
if run_generator 2>/dev/null; then
    print -u2 "Generator overwrote an existing cask without --replace"
    exit 1
fi
after_existing="$(/usr/bin/shasum -a 256 "$output" | /usr/bin/awk '{ print $1 }')"
[[ "$before_existing" == "$after_existing" ]] || {
    print -u2 "Refused overwrite mutated the existing cask"
    exit 1
}

if "$repository_root/scripts/generate-homebrew-cask.sh" \
    --version 1.0.0-beta.1 \
    --release-directory "$release_directory" \
    --output "$test_root/beta.rb" >/dev/null 2>&1; then
    print -u2 "Generator accepted a Beta version"
    exit 1
fi

valid_checksum="$(/bin/cat "$release_directory/$dmg_name.sha256")"
print 'malformed' > "$release_directory/$dmg_name.sha256"
if run_generator --replace 2>/dev/null; then
    print -u2 "Generator accepted a malformed local checksum"
    exit 1
fi
print -r -- "$valid_checksum" > "$release_directory/$dmg_name.sha256"

/bin/cp "$release_directory/$dmg_name" "$public_root/$dmg_name"
/bin/cp "$release_directory/$dmg_name.sha256" "$public_root/$dmg_name.sha256"
print '{"tag_name":"v1.0.0","draft":false,"prerelease":false,"immutable":true}' > "$public_root/release.json"
WINDOWRANGER_TEST_HOMEBREW_RELEASE_INPUTS=1 \
WINDOWRANGER_TEST_HOMEBREW_PUBLIC_ROOT="$public_root" \
    run_generator --verify-public --replace

public_before="$(/usr/bin/shasum -a 256 "$output" | /usr/bin/awk '{ print $1 }')"
print 'different public dmg' > "$public_root/$dmg_name"
if WINDOWRANGER_TEST_HOMEBREW_RELEASE_INPUTS=1 \
    WINDOWRANGER_TEST_HOMEBREW_PUBLIC_ROOT="$public_root" \
    run_generator --verify-public --replace 2>/dev/null; then
    print -u2 "Generator accepted a public artifact that differed from the local release"
    exit 1
fi
public_after="$(/usr/bin/shasum -a 256 "$output" | /usr/bin/awk '{ print $1 }')"
[[ "$public_before" == "$public_after" ]] || {
    print -u2 "Failed public verification mutated the existing cask"
    exit 1
}

/bin/cp "$release_directory/$dmg_name" "$public_root/$dmg_name"
print '{"tag_name":"v1.0.0","draft":false,"prerelease":true,"immutable":true}' > "$public_root/release.json"
if WINDOWRANGER_TEST_HOMEBREW_RELEASE_INPUTS=1 \
    WINDOWRANGER_TEST_HOMEBREW_PUBLIC_ROOT="$public_root" \
    run_generator --verify-public --replace 2>/dev/null; then
    print -u2 "Generator accepted a public prerelease"
    exit 1
fi

print "Stable-only Homebrew Cask generation and public-artifact verification passed."
