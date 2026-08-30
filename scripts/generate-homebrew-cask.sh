#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
script_name="${0:t}"
release_root="${WINDOWRANGER_RELEASE_ROOT:-$repository_root/.build/releases}"
test_release_inputs="${WINDOWRANGER_TEST_HOMEBREW_RELEASE_INPUTS:-0}"
test_public_root="${WINDOWRANGER_TEST_HOMEBREW_PUBLIC_ROOT:-}"
version=""
release_directory=""
output="$repository_root/.build/homebrew/windowranger.rb"
verify_public=false
replace=false
temporary_root=""
temporary_output=""
output_directory=""

cleanup() {
    if [[ -n "$temporary_root" &&
          "$temporary_root" == "${TMPDIR:-/tmp}/windowranger-homebrew-public."* ]]; then
        /bin/rm -R -- "$temporary_root"
    fi
    if [[ -n "$temporary_output" && -n "$output_directory" &&
          "$temporary_output" == "$output_directory/.windowranger-cask."* ]]; then
        /bin/rm -f -- "$temporary_output"
    fi
}
trap cleanup EXIT INT TERM

usage() {
    print "Usage: $script_name --version X.Y.Z [--release-directory PATH] [--output PATH] [--verify-public] [--replace]"
    print ""
    print "Generates the Stable WindowRanger Homebrew Cask from the signed release DMG."
    print "Beta and Dev versions are rejected. --verify-public additionally proves that the"
    print "published GitHub release is Stable, immutable, and byte-identical to the local DMG."
    print "The command never creates a tap, submits a pull request, or publishes anything."
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
        --output)
            (( $# >= 2 )) || { print -u2 "--output requires a value"; exit 2; }
            output="$2"
            shift
            ;;
        --verify-public) verify_public=true ;;
        --replace) replace=true ;;
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
print -r -- "$version" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
    print -u2 "Homebrew publication requires a Stable X.Y.Z version: $version"
    exit 2
}

if [[ -z "$release_directory" ]]; then
    release_directory="$release_root/$version"
fi
release_directory="${release_directory:A}"
output="${output:A}"

dmg_name="WindowRanger-$version.dmg"
checksum_name="$dmg_name.sha256"
local_dmg="$release_directory/$dmg_name"
local_checksum_file="$release_directory/$checksum_name"

[[ -f "$local_dmg" ]] || { print -u2 "Missing Stable release DMG: $local_dmg"; exit 1; }
[[ -f "$local_checksum_file" ]] || {
    print -u2 "Missing Stable release checksum: $local_checksum_file"
    exit 1
}

read_checksum() {
    local checksum_file="$1"
    local expected_name="$2"
    /usr/bin/awk -v expected="$expected_name" '
        NF {
            lines++
            if (NF == 2 && length($1) == 64 && $1 !~ /[^0-9A-Fa-f]/ && $2 == expected) {
                matches++
                checksum = tolower($1)
            }
        }
        END {
            if (lines == 1 && matches == 1) print checksum
            else exit 1
        }
    ' "$checksum_file"
}

expected_checksum="$(read_checksum "$local_checksum_file" "$dmg_name")" || {
    print -u2 "Malformed checksum file; expected one SHA-256 line for $dmg_name"
    exit 1
}
actual_checksum="$(/usr/bin/shasum -a 256 "$local_dmg" | /usr/bin/awk '{ print $1 }')"
[[ "$actual_checksum" == "$expected_checksum" ]] || {
    print -u2 "Local Stable DMG does not match its checksum"
    exit 1
}

if [[ "$verify_public" == true ]]; then
    temporary_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/windowranger-homebrew-public.XXXXXX")"
    public_metadata="$temporary_root/release.json"
    public_dmg="$temporary_root/$dmg_name"
    public_checksum_file="$temporary_root/$checksum_name"

    if [[ "$test_release_inputs" == 1 ]]; then
        [[ -n "$test_public_root" && -d "$test_public_root" ]] || {
            print -u2 "Test public-release root is missing"
            exit 1
        }
        /bin/cp "$test_public_root/release.json" "$public_metadata"
        /bin/cp "$test_public_root/$dmg_name" "$public_dmg"
        /bin/cp "$test_public_root/$checksum_name" "$public_checksum_file"
    else
        api_url="https://api.github.com/repos/AppRanger/windowranger/releases/tags/v$version"
        download_root="https://github.com/AppRanger/windowranger/releases/download/v$version"
        /usr/bin/curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
            -H 'Accept: application/vnd.github+json' \
            -H 'X-GitHub-Api-Version: 2022-11-28' \
            "$api_url" --output "$public_metadata"
        /usr/bin/curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
            "$download_root/$checksum_name" --output "$public_checksum_file"
        /usr/bin/curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
            "$download_root/$dmg_name" --output "$public_dmg"
    fi

    published_tag="$(/usr/bin/plutil -extract tag_name raw -o - "$public_metadata" 2>/dev/null || true)"
    is_draft="$(/usr/bin/plutil -extract draft raw -o - "$public_metadata" 2>/dev/null || true)"
    is_prerelease="$(/usr/bin/plutil -extract prerelease raw -o - "$public_metadata" 2>/dev/null || true)"
    is_immutable="$(/usr/bin/plutil -extract immutable raw -o - "$public_metadata" 2>/dev/null || true)"
    [[ "$published_tag" == "v$version" ]] || { print -u2 "Public release tag is not v$version"; exit 1; }
    [[ "$is_draft" == false ]] || { print -u2 "Public release is still a draft"; exit 1; }
    [[ "$is_prerelease" == false ]] || { print -u2 "Homebrew Cask requires a Stable release"; exit 1; }
    [[ "$is_immutable" == true ]] || { print -u2 "Public release is not immutable"; exit 1; }

    public_expected_checksum="$(read_checksum "$public_checksum_file" "$dmg_name")" || {
        print -u2 "Published checksum file is malformed"
        exit 1
    }
    public_actual_checksum="$(/usr/bin/shasum -a 256 "$public_dmg" | /usr/bin/awk '{ print $1 }')"
    [[ "$public_actual_checksum" == "$public_expected_checksum" ]] || {
        print -u2 "Published Stable DMG does not match its checksum"
        exit 1
    }
    [[ "$public_actual_checksum" == "$actual_checksum" ]] || {
        print -u2 "Published Stable DMG differs from the locally verified release artifact"
        exit 1
    }
fi

if [[ -e "$output" && "$replace" != true ]]; then
    print -u2 "Output already exists; pass --replace to update it: $output"
    exit 1
fi

output_directory="${output:h}"
/bin/mkdir -p "$output_directory"
temporary_output="$(/usr/bin/mktemp "$output_directory/.windowranger-cask.XXXXXX")"

{
    print 'cask "windowranger" do'
    print "  version \"$version\""
    print "  sha256 \"$actual_checksum\""
    print ''
    print '  url "https://github.com/AppRanger/windowranger/releases/download/v#{version}/WindowRanger-#{version}.dmg"'
    print '  name "WindowRanger"'
    print '  desc "Native workspace and window manager"'
    print '  homepage "https://windowranger.com/"'
    print ''
    print '  auto_updates true'
    print '  depends_on macos: :sonoma'
    print ''
    print '  app "WindowRanger.app"'
    print ''
    print '  uninstall quit: "dev.appranger.WindowRanger"'
    print ''
    print '  zap trash: ['
    print '    "~/Library/Caches/com.windowranger.WindowRanger",'
    print '    "~/Library/Caches/dev.appranger.WindowRanger",'
    print '    "~/Library/HTTPStorages/dev.appranger.WindowRanger",'
    print '    "~/Library/HTTPStorages/dev.appranger.WindowRanger.binarycookies",'
    print '    "~/Library/Logs/dev.appranger.WindowRanger",'
    print '    "~/Library/Preferences/com.windowranger.WindowRanger.plist",'
    print '    "~/Library/Preferences/dev.appranger.WindowRanger.plist",'
    print '    "~/Library/Saved Application State/com.windowranger.WindowRanger.savedState",'
    print '    "~/Library/Saved Application State/dev.appranger.WindowRanger.savedState",'
    print '  ]'
    print 'end'
} > "$temporary_output"

/usr/bin/ruby -c "$temporary_output" >/dev/null
/bin/mv -f -- "$temporary_output" "$output"
temporary_output=""

print "Homebrew Cask generated:"
print "  Version: $version"
print "  SHA-256: $actual_checksum"
print "  Output: $output"
print "  Public release: $([[ "$verify_public" == true ]] && print verified || print not-verified)"
