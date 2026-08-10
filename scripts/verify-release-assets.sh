#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
script_name="${0:t}"
release_root="${WINDOWRANGER_RELEASE_ROOT:-$repository_root/.build/releases}"
version=""
release_directory=""
expected_commit=""

usage() {
    print "Usage: $script_name --version VERSION [--release-directory PATH] [--expected-commit SHA]"
    print ""
    print "Verifies a WindowRanger release asset set, checksums, and provenance manifest."
}

while (( $# > 0 )); do
    case "$1" in
        --version)
            (( $# >= 2 )) || { print -u2 "--version requires a value"; exit 2; }
            version="$2"
            shift
            ;;
        --release-directory)
            (( $# >= 2 )) || { print -u2 "--release-directory requires a value"; exit 2; }
            release_directory="$2"
            shift
            ;;
        --expected-commit)
            (( $# >= 2 )) || { print -u2 "--expected-commit requires a value"; exit 2; }
            expected_commit="$2"
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
print -r -- "$version" | /usr/bin/grep -Eq \
    '^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[1-9][0-9]*)?$' || {
    print -u2 "Version must be X.Y.Z or X.Y.Z-beta.N: $version"
    exit 2
}

if [[ -n "$expected_commit" ]]; then
    print -r -- "$expected_commit" | /usr/bin/grep -Eq '^[0-9a-f]{40}$' || {
        print -u2 "Expected commit must be a full lowercase Git SHA: $expected_commit"
        exit 2
    }
fi

[[ -n "$release_directory" ]] || release_directory="$release_root/$version"
[[ -d "$release_directory" ]] || {
    print -u2 "Release directory not found: $release_directory"
    exit 1
}

archive_name="WindowRanger-$version.zip"
archive="$release_directory/$archive_name"
archive_checksum_file="$archive.sha256"
dmg_name="WindowRanger-$version.dmg"
dmg="$release_directory/$dmg_name"
dmg_checksum_file="$dmg.sha256"
manifest="$release_directory/WindowRanger-$version.release.txt"

for required_file in "$archive" "$archive_checksum_file" "$dmg" "$dmg_checksum_file" "$manifest"; do
    [[ -f "$required_file" ]] || { print -u2 "Missing release asset: $required_file"; exit 1; }
done

manifest_value() {
    local key="$1"
    local count
    local value

    count="$(/usr/bin/awk -F= -v key="$key" '$1 == key { count += 1 } END { print count + 0 }' "$manifest")"
    [[ "$count" == "1" ]] || {
        print -u2 "Manifest must contain exactly one '$key' field; found $count"
        return 1
    }
    value="$(/usr/bin/awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print }' "$manifest")"
    [[ -n "$value" ]] || {
        print -u2 "Manifest field '$key' must not be empty"
        return 1
    }
    print -r -- "$value"
}

base_version="${version%%-*}"
expected_channel="stable"
[[ "$version" == *-beta.* ]] && expected_channel="beta"

manifest_product="$(manifest_value product)"
manifest_channel="$(manifest_value channel)"
manifest_version="$(manifest_value version)"
manifest_bundle_version="$(manifest_value bundle_version)"
manifest_build_number="$(manifest_value build_number)"
manifest_commit="$(manifest_value commit)"
manifest_xcode="$(manifest_value xcode)"
manifest_architectures="$(manifest_value architectures)"
manifest_archive="$(manifest_value archive)"
manifest_archive_checksum="$(manifest_value archive_sha256)"
manifest_dmg="$(manifest_value dmg)"
manifest_dmg_checksum="$(manifest_value dmg_sha256)"

[[ "$manifest_product" == "WindowRanger" ]] || { print -u2 "Unexpected product: $manifest_product"; exit 1; }
[[ "$manifest_channel" == "$expected_channel" ]] || { print -u2 "Unexpected channel: $manifest_channel"; exit 1; }
[[ "$manifest_version" == "$version" ]] || { print -u2 "Unexpected version: $manifest_version"; exit 1; }
[[ "$manifest_bundle_version" == "$base_version" ]] || {
    print -u2 "Unexpected bundle version: $manifest_bundle_version"
    exit 1
}
print -r -- "$manifest_build_number" | /usr/bin/grep -Eq '^[1-9][0-9]*$' || {
    print -u2 "Invalid build number in manifest: $manifest_build_number"
    exit 1
}
print -r -- "$manifest_commit" | /usr/bin/grep -Eq '^[0-9a-f]{40}$' || {
    print -u2 "Invalid commit in manifest: $manifest_commit"
    exit 1
}
[[ -z "$expected_commit" || "$manifest_commit" == "$expected_commit" ]] || {
    print -u2 "Manifest commit $manifest_commit does not match expected commit $expected_commit"
    exit 1
}
[[ "$manifest_architectures" == *arm64* && "$manifest_architectures" == *x86_64* ]] || {
    print -u2 "Manifest does not describe a universal app: $manifest_architectures"
    exit 1
}
[[ "$manifest_archive" == "$archive_name" ]] || { print -u2 "Unexpected archive name: $manifest_archive"; exit 1; }
[[ "$manifest_dmg" == "$dmg_name" ]] || { print -u2 "Unexpected DMG name: $manifest_dmg"; exit 1; }

archive_checksum="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{ print $1 }')"
dmg_checksum="$(/usr/bin/shasum -a 256 "$dmg" | /usr/bin/awk '{ print $1 }')"
archive_checksum_line="$(/usr/bin/tr -d '\r\n' < "$archive_checksum_file")"
dmg_checksum_line="$(/usr/bin/tr -d '\r\n' < "$dmg_checksum_file")"

[[ "$archive_checksum_line" == "$archive_checksum  $archive_name" ]] || {
    print -u2 "Archive checksum file does not match $archive_name"
    exit 1
}
[[ "$dmg_checksum_line" == "$dmg_checksum  $dmg_name" ]] || {
    print -u2 "DMG checksum file does not match $dmg_name"
    exit 1
}
[[ "$manifest_archive_checksum" == "$archive_checksum" ]] || {
    print -u2 "Manifest archive checksum does not match $archive_name"
    exit 1
}
[[ "$manifest_dmg_checksum" == "$dmg_checksum" ]] || {
    print -u2 "Manifest DMG checksum does not match $dmg_name"
    exit 1
}

print "Release assets verified:"
print "  Version: $manifest_version"
print "  Channel: $manifest_channel"
print "  Build: $manifest_build_number"
print "  Commit: $manifest_commit"
print "  Toolchain: $manifest_xcode"
print "  Archive SHA-256: $archive_checksum"
print "  DMG SHA-256: $dmg_checksum"
