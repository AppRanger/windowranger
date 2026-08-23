#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
script_name="${0:t}"
mode="${1:---quick}"

usage() {
    print "Usage: $script_name [--quick|--full]"
    print ""
    print -- "--quick  Generate the project, check script syntax/test isolation, and run all tests."
    print -- "--full   Also run static analysis, build unsigned Release, and verify both DMGs."
}

case "$mode" in
    --quick|--full)
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        print -u2 "Unknown mode: $mode"
        usage >&2
        exit 2
        ;;
esac

command -v xcodegen >/dev/null || {
    print -u2 "XcodeGen is required. Install it before running local verification."
    exit 1
}
command -v xcodebuild >/dev/null || {
    print -u2 "xcodebuild is required. Install/select Xcode before running local verification."
    exit 1
}

cd "$repository_root"

print "Checking shell syntax..."
zsh -n scripts/*.sh .githooks/*

print "Verifying the release build-number ledger..."
./scripts/verify-release-build-registry.sh

print "Verifying the Sparkle feed ordering and failure workflow..."
./scripts/verify-sparkle-feed-workflow.sh

print "Generating the Xcode project..."
xcodegen generate

print "Verifying the non-hosted test boundary..."
./scripts/verify-test-isolation.sh

print "Running the complete non-hosted test suite..."
xcodebuild \
    -project WindowRanger.xcodeproj \
    -scheme WindowRanger \
    -configuration Debug \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    test

if [[ "$mode" == "--quick" ]]; then
    print "Local quick verification passed."
    exit 0
fi

print "Running Release static analysis..."
xcodebuild \
    -project WindowRanger.xcodeproj \
    -scheme WindowRanger \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    analyze

print "Building the unsigned Release configuration in canonical DerivedData..."
xcodebuild \
    -project WindowRanger.xcodeproj \
    -scheme WindowRanger \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build

release_build_directory="$(
    xcodebuild \
        -project WindowRanger.xcodeproj \
        -scheme WindowRanger \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -showBuildSettings \
    | /usr/bin/awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / && !found { print $2; found = 1 }'
)"
release_app="$release_build_directory/WindowRanger.app"
[[ -d "$release_app" ]] || {
    print -u2 "Unsigned Release app was not found in canonical DerivedData: $release_app"
    exit 1
}

print "Building and verifying unsigned Stable/Beta DMG smoke packages..."
./scripts/install-dmg-tools.sh
package_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/windowranger-local-ci.XXXXXX")"
cleanup() {
    [[ "$package_root" == "${TMPDIR:-/tmp}/windowranger-local-ci."* ]] || return
    /bin/rm -rf "$package_root"
}
trap cleanup EXIT INT TERM

stable_dmg="$package_root/WindowRanger-unsigned-stable.dmg"
beta_dmg="$package_root/WindowRanger-unsigned-beta.dmg"
./scripts/build-dmg.sh --app "$release_app" --channel stable --output "$stable_dmg"
./scripts/build-dmg.sh --app "$release_app" --channel beta --output "$beta_dmg"
./scripts/verify-dmg.sh --dmg "$stable_dmg"
./scripts/verify-dmg.sh --dmg "$beta_dmg"

print "Local full verification passed."
