#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
script_name="${0:t}"
release_root="${WINDOWRANGER_RELEASE_ROOT:-$repository_root/.build/releases}"
version=""
notes_file=""

usage() {
    print "Usage: $script_name --version VERSION [--notes-file PATH]"
    print ""
    print "Creates a draft GitHub release from an already pushed tag and notarized local artifacts."
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
manifest="$release_directory/WindowRanger-$version.release.txt"

[[ -f "$archive" ]] || { print -u2 "Missing notarized release archive: $archive"; exit 1; }
[[ -f "$checksum" ]] || { print -u2 "Missing release checksum: $checksum"; exit 1; }
[[ -f "$manifest" ]] || { print -u2 "Missing release manifest: $manifest"; exit 1; }
[[ -z "$notes_file" || -f "$notes_file" ]] || { print -u2 "Notes file not found: $notes_file"; exit 1; }
[[ -z "$(/usr/bin/git -C "$repository_root" status --porcelain --untracked-files=normal)" ]] || {
    print -u2 "The worktree must be clean before creating a GitHub release"
    exit 1
}

tag_commit="$(/usr/bin/git -C "$repository_root" rev-list -n 1 "$tag" 2>/dev/null || true)"
head_commit="$(/usr/bin/git -C "$repository_root" rev-parse HEAD)"
[[ -n "$tag_commit" ]] || { print -u2 "Local tag does not exist: $tag"; exit 1; }
[[ "$tag_commit" == "$head_commit" ]] || { print -u2 "$tag does not point to HEAD"; exit 1; }

remote_tag="$(/usr/bin/git -C "$repository_root" ls-remote --tags origin "refs/tags/$tag" | /usr/bin/awk '{ print $1 }')"
[[ -n "$remote_tag" ]] || { print -u2 "Tag has not been pushed to origin: $tag"; exit 1; }

repo_name="$(cd "$repository_root" && gh repo view --json nameWithOwner --jq .nameWithOwner)"
if gh release view "$tag" --repo "$repo_name" >/dev/null 2>&1; then
    print -u2 "A GitHub release already exists for $tag"
    exit 1
fi

typeset -a release_arguments
release_arguments=(
    release create "$tag" "$archive" "$checksum" "$manifest"
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
print "Draft release created: $release_url"
print "Review the attached ZIP, checksum, title, and notes on GitHub before publishing it."
