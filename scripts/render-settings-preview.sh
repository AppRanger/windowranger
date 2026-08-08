#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
project_file="$repository_root/WindowManager.xcodeproj"
output_directory="${1:-$repository_root/.build/settings-redesign-previews}"
derived_data_directory="${WINDOWMANAGER_CANONICAL_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/WindowManager-bwwhwrakaohlokbcoipksphbkdvw}"

"$repository_root/scripts/verify-test-isolation.sh"

/usr/bin/xcodebuild \
    -project "$project_file" \
    -scheme WindowManager \
    -configuration Debug \
    -destination 'platform=macOS' \
    -only-testing:WindowManagerTests/WorkspaceSettingsVisualSnapshotTests \
    CODE_SIGNING_ALLOWED=NO \
    test

test_bundle="$derived_data_directory/Build/Products/Debug/WindowManagerTests.xctest"
[[ -d "$test_bundle" ]] || {
    print -u2 "Missing non-hosted test bundle: $test_bundle"
    exit 1
}

/bin/mkdir -p "$output_directory"
WINDOWMANAGER_SETTINGS_SNAPSHOT_DIR="$output_directory" \
    /usr/bin/xcrun xctest \
    -XCTest WindowManagerTests.WorkspaceSettingsVisualSnapshotTests/testOffscreenProductionWorkspaceSettings \
    "$test_bundle"

print "Rendered the native Workspaces Settings preview to: $output_directory"
