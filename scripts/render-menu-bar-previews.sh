#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
project_file="$repository_root/WindowManager.xcodeproj"
output_directory="${1:-$repository_root/.build/menu-bar-previews}"
derived_data_directory="${WINDOWMANAGER_PREVIEW_DERIVED_DATA:-$repository_root/.build/MenuBarPreviewDerivedData}"

"$repository_root/scripts/verify-test-isolation.sh"

/usr/bin/xcodebuild \
    -project "$project_file" \
    -scheme WindowManager \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data_directory" \
    -only-testing:WindowManagerTests/MenuBarVisualSnapshotTests \
    CODE_SIGNING_ALLOWED=NO \
    test

test_bundle="$derived_data_directory/Build/Products/Debug/WindowManagerTests.xctest"

[[ -d "$test_bundle" ]] || {
    print -u2 "Missing non-hosted test bundle: $test_bundle"
    exit 1
}

/bin/mkdir -p "$output_directory"
WINDOWMANAGER_MENU_SNAPSHOT_DIR="$output_directory" \
    /usr/bin/xcrun xctest \
    -XCTest WindowManagerTests.MenuBarVisualSnapshotTests/testOffscreenProductionMenuBarComponents \
    "$test_bundle"

print "Rendered Compact, Medium, and Full previews to: $output_directory"
