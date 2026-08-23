#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
project_file="$repository_root/WindowRanger.xcodeproj"
output_directory="${1:-$repository_root/.build/onboarding-design-qa/implementation}"
derived_data_directory="${WINDOWRANGER_PREVIEW_DERIVED_DATA:-$repository_root/.build/OnboardingPreviewDerivedData}"

"$repository_root/scripts/verify-test-isolation.sh"

/usr/bin/xcodebuild \
    -project "$project_file" \
    -scheme WindowRanger \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data_directory" \
    -only-testing:WindowRangerTests/OnboardingFlowTests/testOffscreenProductionOnboardingStages \
    CODE_SIGNING_ALLOWED=NO \
    test

test_bundle="$derived_data_directory/Build/Products/Debug/WindowRangerTests.xctest"
[[ -d "$test_bundle" ]] || {
    print -u2 "Missing non-hosted test bundle: $test_bundle"
    exit 1
}

/bin/mkdir -p "$output_directory"
WINDOWRANGER_ONBOARDING_SNAPSHOT_DIR="$output_directory" \
    /usr/bin/xcrun xctest \
    -XCTest WindowRangerTests.OnboardingFlowTests/testOffscreenProductionOnboardingStages \
    "$test_bundle"

print "Rendered all seven native onboarding stages to: $output_directory"
