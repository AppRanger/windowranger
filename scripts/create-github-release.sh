#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
script_name="${0:t}"
release_root="${WINDOWRANGER_RELEASE_ROOT:-$repository_root/.build/releases}"
version=""
notes_file=""
verify_existing=false

usage() {
    print "Usage: $script_name --version VERSION [--notes-file PATH] [--verify-existing]"
    print ""
    print "Creates a draft GitHub release from an already pushed tag and notarized local artifacts."
    print "Use --verify-existing to download and verify an existing release without changing it."
    print "It never publishes the draft or changes repository visibility."
}

while (( $# > 0 )); do
    case "$1" in
        --version)
            (( $# >= 2 )) || { print -u2 "--version requires a value"; exit 2; }
            version="$2"
            shift
            ;;
        --notes-file)
            (( $# >= 2 )) || { print -u2 "--notes-file requires a value"; exit 2; }
            notes_file="$2"
            shift
            ;;
        --verify-existing) verify_existing=true ;;
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

tag="v$version"
release_directory="$release_root/$version"
archive="$release_directory/WindowRanger-$version.zip"
checksum="$archive.sha256"
dmg="$release_directory/WindowRanger-$version.dmg"
dmg_checksum="$dmg.sha256"
manifest="$release_directory/WindowRanger-$version.release.txt"
verifier="$repository_root/scripts/verify-release-assets.sh"
typeset -a expected_assets
expected_assets=(
    "WindowRanger-$version.dmg"
    "WindowRanger-$version.dmg.sha256"
    "WindowRanger-$version.release.txt"
    "WindowRanger-$version.zip"
    "WindowRanger-$version.zip.sha256"
)

[[ -x "$verifier" ]] || { print -u2 "Release verifier is not executable: $verifier"; exit 1; }

tag_commit="$(/usr/bin/git -C "$repository_root" rev-list -n 1 "$tag" 2>/dev/null || true)"
[[ -n "$tag_commit" ]] || { print -u2 "Local tag does not exist: $tag"; exit 1; }

remote_tag_commit="$(
    /usr/bin/git -C "$repository_root" ls-remote --tags origin "refs/tags/$tag^{}" |
        /usr/bin/awk '{ print $1 }'
)"
if [[ -z "$remote_tag_commit" ]]; then
    remote_tag_commit="$(
        /usr/bin/git -C "$repository_root" ls-remote --tags origin "refs/tags/$tag" |
            /usr/bin/awk '{ print $1 }'
    )"
fi
[[ -n "$remote_tag_commit" ]] || { print -u2 "Tag has not been pushed to origin: $tag"; exit 1; }
[[ "$remote_tag_commit" == "$tag_commit" ]] || {
    print -u2 "Remote tag $tag does not resolve to the local tag commit"
    exit 1
}

repo_name="$(cd "$repository_root" && gh repo view --json nameWithOwner --jq .nameWithOwner)"

verify_github_assets() {
    local download_directory
    local expected_asset_list
    local remote_asset_list

    expected_asset_list="$(printf '%s\n' "${expected_assets[@]}" | LC_ALL=C /usr/bin/sort)"
    remote_asset_list="$(
        gh release view "$tag" --repo "$repo_name" --json assets --jq '.assets[].name' |
            LC_ALL=C /usr/bin/sort
    )"
    [[ "$remote_asset_list" == "$expected_asset_list" ]] || {
        print -u2 "GitHub release assets do not match the expected five-file set"
        print -u2 "Expected:"
        print -u2 -r -- "$expected_asset_list"
        print -u2 "Found:"
        print -u2 -r -- "$remote_asset_list"
        return 1
    }

    download_directory="$(/usr/bin/mktemp -d /tmp/windowranger-release-download.XXXXXX)"
    if ! gh release download "$tag" --repo "$repo_name" --dir "$download_directory"; then
        /bin/rm -R -- "$download_directory"
        return 1
    fi
    if ! "$verifier" \
        --version "$version" \
        --release-directory "$download_directory" \
        --expected-commit "$tag_commit"; then
        /bin/rm -R -- "$download_directory"
        return 1
    fi
    /bin/rm -R -- "$download_directory"
}

if [[ "$verify_existing" == true ]]; then
    gh release view "$tag" --repo "$repo_name" >/dev/null 2>&1 || {
        print -u2 "No GitHub release exists for $tag"
        exit 1
    }
    print "Downloading and verifying the existing GitHub release for $tag..."
    verify_github_assets
    print "GitHub release assets round-trip verified: $tag"
    exit 0
fi

[[ -f "$archive" ]] || { print -u2 "Missing notarized release archive: $archive"; exit 1; }
[[ -f "$checksum" ]] || { print -u2 "Missing release checksum: $checksum"; exit 1; }
[[ -f "$dmg" ]] || { print -u2 "Missing notarized release DMG: $dmg"; exit 1; }
[[ -f "$dmg_checksum" ]] || { print -u2 "Missing DMG checksum: $dmg_checksum"; exit 1; }
[[ -f "$manifest" ]] || { print -u2 "Missing release manifest: $manifest"; exit 1; }
[[ -z "$notes_file" || -f "$notes_file" ]] || { print -u2 "Notes file not found: $notes_file"; exit 1; }
[[ -z "$(/usr/bin/git -C "$repository_root" status --porcelain --untracked-files=normal)" ]] || {
    print -u2 "The worktree must be clean before creating a GitHub release"
    exit 1
}

head_commit="$(/usr/bin/git -C "$repository_root" rev-parse HEAD)"
[[ "$tag_commit" == "$head_commit" ]] || { print -u2 "$tag does not point to HEAD"; exit 1; }
"$verifier" --version "$version" --release-directory "$release_directory" --expected-commit "$head_commit"

if gh release view "$tag" --repo "$repo_name" >/dev/null 2>&1; then
    print -u2 "A GitHub release already exists for $tag"
    print -u2 "Verify it without changing it using:"
    print -u2 "  ./$script_name --version $version --verify-existing"
    exit 1
fi

typeset -a release_arguments
release_arguments=(
    release create "$tag" "$dmg" "$dmg_checksum" "$archive" "$checksum" "$manifest"
    --repo "$repo_name"
    --verify-tag
    --draft
    --title "WindowRanger $version"
)

if [[ "$version" == *-beta.* ]]; then
    release_arguments+=(--prerelease)
fi
if [[ -n "$notes_file" ]]; then
    release_arguments+=(--notes-file "$notes_file")
else
    release_arguments+=(--generate-notes)
fi

print "Creating a draft GitHub release for $tag..."
release_url="$(gh "${release_arguments[@]}")"
print "Round-trip verifying the uploaded GitHub assets..."
verify_github_assets || {
    print -u2 "The draft exists, but its downloaded assets did not pass verification."
    print -u2 "Inspect the draft and rerun with --verify-existing after correcting it."
    exit 1
}
print "Draft release created: $release_url"
print "The downloaded DMG, ZIP, checksums, and manifest match the tag and local provenance."
print "Review the title, notes, and remaining human release gates on GitHub before publishing it."
