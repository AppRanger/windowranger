#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
script_name="${0:t}"
project_file="$repository_root/WindowRanger.xcodeproj"
export_options="$repository_root/config/ExportOptions-DeveloperID.plist"
release_team_id="$(/usr/libexec/PlistBuddy -c 'Print :teamID' "$export_options" 2>/dev/null || true)"
release_bundle_id="com.windowranger.WindowRanger"
release_root="${WINDOWRANGER_RELEASE_ROOT:-$repository_root/.build/releases}"
developer_directory="${WINDOWRANGER_DEVELOPER_DIR:-${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}}"
dmg_tool_root="${WINDOWRANGER_DMG_TOOL_ROOT:-$repository_root/.build/dmg-tools}"
dmgbuild="${WINDOWRANGER_DMGBUILD:-$dmg_tool_root/bin/dmgbuild}"
version=""
build_number=""
notary_profile=""
preflight_only=false

usage() {
    print "Usage: $script_name --version VERSION --build-number NUMBER --notary-profile PROFILE [--preflight]"
    print ""
    print "Builds, Developer ID-signs, notarizes, staples, and packages a Stable or Beta release."
    print "The command never tags, pushes, creates a GitHub release, or changes repository visibility."
    print ""
    print "Environment overrides:"
    print "  WINDOWRANGER_DEVELOPER_DIR   Stable Xcode Developer directory"
    print "  WINDOWRANGER_RELEASE_ROOT   Artifact root (default: .build/releases)"
    print "  WINDOWRANGER_DMG_TOOL_ROOT  dmgbuild virtual environment (default: .build/dmg-tools)"
}

while (( $# > 0 )); do
    case "$1" in
        --version)
            (( $# >= 2 )) || { print -u2 "--version requires a value"; exit 2; }
            version="$2"
            shift
            ;;
        --build-number)
            (( $# >= 2 )) || { print -u2 "--build-number requires a value"; exit 2; }
            build_number="$2"
            shift
            ;;
        --notary-profile)
            (( $# >= 2 )) || { print -u2 "--notary-profile requires a value"; exit 2; }
            notary_profile="$2"
            shift
            ;;
        --preflight) preflight_only=true ;;
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
[[ -n "$build_number" ]] || { print -u2 "Missing --build-number"; exit 2; }
[[ -n "$notary_profile" ]] || { print -u2 "Missing --notary-profile"; exit 2; }

print -r -- "$version" | /usr/bin/grep -Eq \
    '^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[1-9][0-9]*)?$' || {
    print -u2 "Version must be X.Y.Z or X.Y.Z-beta.N: $version"
    exit 2
}
print -r -- "$build_number" | /usr/bin/grep -Eq '^[1-9][0-9]*$' || {
    print -u2 "Build number must be a positive integer: $build_number"
    exit 2
}

base_version="${version%%-*}"
channel="stable"
expected_branch="main"
if [[ "$version" == *-beta.* ]]; then
    channel="beta"
    expected_branch="release/$base_version"
fi

typeset -a blockers

require_command() {
    command -v "$1" >/dev/null 2>&1 || blockers+=("Missing required command: $1")
}

for required_command in git xcodegen xcodebuild codesign security ditto shasum hdiutil; do
    require_command "$required_command"
done

[[ -d "$developer_directory" ]] || blockers+=("Xcode Developer directory does not exist: $developer_directory")
[[ "$developer_directory:l" != *beta* ]] || blockers+=(
    "Release builds must use stable Xcode, not: $developer_directory"
)
[[ -f "$export_options" ]] || blockers+=("Missing export options: $export_options")
[[ -n "$release_team_id" ]] || blockers+=("Export options do not declare a release team ID")
[[ -x "$dmgbuild" ]] || blockers+=(
    "DMG tools are not installed; run ./scripts/install-dmg-tools.sh"
)
[[ -f "$repository_root/Brand/WindowRanger/dmg/backgrounds/$channel-background.png" ]] || blockers+=(
    "Missing $channel DMG background"
)

current_branch="$(/usr/bin/git -C "$repository_root" branch --show-current)"
[[ "$current_branch" == "$expected_branch" ]] || blockers+=(
    "$channel version $version must be built from $expected_branch, not ${current_branch:-detached HEAD}"
)

working_tree_state="$(/usr/bin/git -C "$repository_root" status --porcelain --untracked-files=normal)"
[[ -z "$working_tree_state" ]] || blockers+=("The release worktree must be clean and committed")

identity_output="$(/usr/bin/security find-identity -v -p codesigning 2>&1 || true)"
matching_identities="$(
    print -r -- "$identity_output" |
        /usr/bin/grep -E "Developer ID Application:.*\($release_team_id\)" || true
)"
identity_count="$(print -r -- "$matching_identities" | /usr/bin/grep -c . || true)"
[[ "$identity_count" == "1" ]] || blockers+=(
    "Expected exactly one valid Developer ID Application identity for team $release_team_id; found $identity_count"
)
signing_identity_hash="$(print -r -- "$matching_identities" | /usr/bin/awk 'NR == 1 { print $2 }')"

if [[ -d "$developer_directory" ]]; then
    DEVELOPER_DIR="$developer_directory" /usr/bin/xcrun notarytool history \
        --keychain-profile "$notary_profile" \
        --output-format json >/dev/null 2>&1 || blockers+=(
        "Notary keychain profile '$notary_profile' is missing or invalid"
    )
fi

if (( ${#blockers} > 0 )); then
    print -u2 "Release preflight failed:"
    for blocker in "${blockers[@]}"; do
        print -u2 "  - $blocker"
    done
    exit 1
fi

xcode_version="$(DEVELOPER_DIR="$developer_directory" /usr/bin/xcodebuild -version | /usr/bin/head -n 1)"
print "Release preflight passed:"
print "  Channel: $channel"
print "  Version: $version"
print "  Build: $build_number"
print "  Branch: $current_branch"
print "  Toolchain: $xcode_version"
print "  Signing team: $release_team_id"
print "  Notary keychain profile: $notary_profile"

if [[ "$preflight_only" == true ]]; then
    exit 0
fi

release_directory="$release_root/$version"
if [[ -e "$release_directory" ]]; then
    print -u2 "Release output already exists; move it aside or choose a new version: $release_directory"
    exit 1
fi
/bin/mkdir -p "$release_root"
/bin/mkdir "$release_directory"

derived_data="$release_directory/DerivedData"
archive_path="$release_directory/WindowRanger.xcarchive"
export_path="$release_directory/export"
notary_archive="$release_directory/WindowRanger-$version-notary.zip"
final_archive_name="WindowRanger-$version.zip"
final_archive="$release_directory/$final_archive_name"
checksum_name="$final_archive_name.sha256"
checksum_file="$release_directory/$checksum_name"
final_dmg_name="WindowRanger-$version.dmg"
final_dmg="$release_directory/$final_dmg_name"
dmg_checksum_name="$final_dmg_name.sha256"
dmg_checksum_file="$release_directory/$dmg_checksum_name"
manifest_name="WindowRanger-$version.release.txt"
manifest_file="$release_directory/$manifest_name"
entitlements_file="$release_directory/WindowRanger.entitlements.plist"

notarize_and_record() {
    local artifact="$1"
    local label="$2"
    local result_file="$release_directory/WindowRanger-$version-$label-notary-result.json"
    local log_file="$release_directory/WindowRanger-$version-$label-notary-log.json"
    local submission_id
    local status
    local issue_count

    DEVELOPER_DIR="$developer_directory" /usr/bin/xcrun notarytool submit "$artifact" \
        --keychain-profile "$notary_profile" \
        --wait \
        --output-format json > "$result_file"

    submission_id="$(/usr/bin/plutil -extract id raw -o - "$result_file")"
    status="$(/usr/bin/plutil -extract status raw -o - "$result_file")"
    [[ "$status" == "Accepted" ]] || {
        print -u2 "$label notarization was not accepted: $status"
        return 1
    }

    DEVELOPER_DIR="$developer_directory" /usr/bin/xcrun notarytool log "$submission_id" "$log_file" \
        --keychain-profile "$notary_profile"
    issue_count="$(
        /usr/bin/awk '{
            line = $0
            while (match(line, /"severity"[[:space:]]*:/)) {
                count += 1
                line = substr(line, RSTART + RLENGTH)
            }
        } END { print count + 0 }' "$log_file"
    )"
    [[ "$issue_count" == "0" ]] || {
        print -u2 "$label notarization log contains $issue_count issue(s): $log_file"
        return 1
    }

    print "$label notarization accepted with zero logged issues: $submission_id"
    REPLY="$submission_id"
}

print "Generating the Xcode project..."
(cd "$repository_root" && /opt/homebrew/bin/xcodegen generate 2>/dev/null) || \
    (cd "$repository_root" && xcodegen generate)

print "Verifying the non-hosted test boundary..."
DEVELOPER_DIR="$developer_directory" "$repository_root/scripts/verify-test-isolation.sh"

print "Running the complete non-hosted test suite..."
DEVELOPER_DIR="$developer_directory" /usr/bin/xcodebuild \
    -project "$project_file" \
    -scheme WindowRanger \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data/tests" \
    CODE_SIGNING_ALLOWED=NO \
    test

print "Running static analysis..."
DEVELOPER_DIR="$developer_directory" /usr/bin/xcodebuild \
    -project "$project_file" \
    -scheme WindowRanger \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data/analyze" \
    CODE_SIGNING_ALLOWED=NO \
    analyze

print "Creating the signed Release archive..."
DEVELOPER_DIR="$developer_directory" /usr/bin/xcodebuild \
    -project "$project_file" \
    -scheme WindowRanger \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive_path" \
    -allowProvisioningUpdates \
    MARKETING_VERSION="$base_version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    archive

print "Exporting with Developer ID..."
DEVELOPER_DIR="$developer_directory" /usr/bin/xcodebuild \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates

exported_app="$export_path/WindowRanger.app"
[[ -d "$exported_app" ]] || { print -u2 "Exported app not found: $exported_app"; exit 1; }

/usr/bin/codesign --verify --deep --strict "$exported_app"
signature_details="$(/usr/bin/codesign -dv --verbose=4 "$exported_app" 2>&1)"
[[ "$signature_details" == *"Authority=Developer ID Application:"* ]] || {
    print -u2 "Exported app is not signed with Developer ID Application"
    exit 1
}
[[ "$signature_details" == *"Identifier=$release_bundle_id"* ]] || {
    print -u2 "Exported app has the wrong signing identifier"
    exit 1
}
[[ "$signature_details" == *"TeamIdentifier=$release_team_id"* ]] || {
    print -u2 "Exported app is signed by the wrong team"
    exit 1
}

app_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$exported_app/Contents/Info.plist")"
[[ "$app_bundle_id" == "$release_bundle_id" ]] || {
    print -u2 "Unexpected app bundle identifier: $app_bundle_id"
    exit 1
}

app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$exported_app/Contents/Info.plist")"
app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$exported_app/Contents/Info.plist")"
[[ "$app_version" == "$base_version" ]] || { print -u2 "Unexpected app version: $app_version"; exit 1; }
[[ "$app_build" == "$build_number" ]] || { print -u2 "Unexpected app build: $app_build"; exit 1; }

architectures="$(/usr/bin/lipo -archs "$exported_app/Contents/MacOS/WindowRanger")"
[[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || {
    print -u2 "Release must be universal; found architectures: $architectures"
    exit 1
}

/usr/bin/codesign -d --entitlements :- "$exported_app" > "$entitlements_file" 2>/dev/null
get_task_allow="$(/usr/bin/plutil -extract com.apple.security.get-task-allow raw -o - "$entitlements_file" 2>/dev/null || true)"
[[ "$get_task_allow" != "true" ]] || {
    print -u2 "Release contains the forbidden com.apple.security.get-task-allow entitlement"
    exit 1
}

print "Submitting the Developer ID app for notarization..."
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$exported_app" "$notary_archive"
notarize_and_record "$notary_archive" app
app_notarization_id="$REPLY"

print "Stapling and validating the notarization ticket..."
DEVELOPER_DIR="$developer_directory" /usr/bin/xcrun stapler staple "$exported_app"
DEVELOPER_DIR="$developer_directory" /usr/bin/xcrun stapler validate "$exported_app"
/usr/sbin/spctl -a -vv -t exec "$exported_app"

print "Creating the immutable release archive..."
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$exported_app" "$final_archive"

print "Creating the styled $channel DMG..."
WINDOWRANGER_DMGBUILD="$dmgbuild" "$repository_root/scripts/build-dmg.sh" \
    --app "$exported_app" \
    --channel "$channel" \
    --output "$final_dmg"

print "Signing the DMG container with Developer ID..."
/usr/bin/codesign --force \
    --sign "$signing_identity_hash" \
    --timestamp \
    --identifier "com.windowranger.WindowRanger.dmg" \
    "$final_dmg"
/usr/bin/codesign --verify --verbose=2 "$final_dmg"

print "Notarizing and stapling the DMG container..."
notarize_and_record "$final_dmg" dmg
dmg_notarization_id="$REPLY"
DEVELOPER_DIR="$developer_directory" /usr/bin/xcrun stapler staple "$final_dmg"
DEVELOPER_DIR="$developer_directory" /usr/bin/xcrun stapler validate "$final_dmg"
/usr/sbin/spctl -a -vv -t open --context context:primary-signature "$final_dmg"
"$repository_root/scripts/verify-dmg.sh" --dmg "$final_dmg"

print "Writing release checksums and provenance..."
(cd "$release_directory" && /usr/bin/shasum -a 256 "$final_archive_name" > "$checksum_name")
(cd "$release_directory" && /usr/bin/shasum -a 256 "$final_dmg_name" > "$dmg_checksum_name")
commit_sha="$(/usr/bin/git -C "$repository_root" rev-parse HEAD)"
archive_checksum="$(/usr/bin/awk '{ print $1 }' "$checksum_file")"
dmg_checksum="$(/usr/bin/awk '{ print $1 }' "$dmg_checksum_file")"
{
    print "product=WindowRanger"
    print "channel=$channel"
    print "version=$version"
    print "bundle_version=$base_version"
    print "build_number=$build_number"
    print "commit=$commit_sha"
    print "xcode=$xcode_version"
    print "architectures=$architectures"
    print "archive=$final_archive_name"
    print "archive_sha256=$archive_checksum"
    print "dmg=$final_dmg_name"
    print "dmg_sha256=$dmg_checksum"
    print "app_notarization_id=$app_notarization_id"
    print "dmg_notarization_id=$dmg_notarization_id"
    print "notarization_issue_count=0"
} > "$manifest_file"

print "Release package ready:"
print "  App: $exported_app"
print "  Archive: $final_archive"
print "  Checksum: $checksum_file"
print "  DMG: $final_dmg"
print "  DMG checksum: $dmg_checksum_file"
print "  Manifest: $manifest_file"
print ""
print "Next: test this exact DMG and archive, create and push tag v$version, then run:"
print "  ./scripts/create-github-release.sh --version $version"
