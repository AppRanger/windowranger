#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
scheme_file="$repository_root/WindowManager.xcodeproj/xcshareddata/xcschemes/WindowManager.xcscheme"
project_file="$repository_root/WindowManager.xcodeproj"

[[ -f "$scheme_file" ]] || {
    print -u2 "Missing generated scheme: $scheme_file"
    exit 1
}

app_test_entries=$(/usr/bin/xmllint --xpath \
    'count(//BuildActionEntry[@buildForTesting="YES"]/BuildableReference[@BlueprintName="WindowManager"])' \
    "$scheme_file")
test_bundle_entries=$(/usr/bin/xmllint --xpath \
    'count(//BuildActionEntry[@buildForTesting="YES"]/BuildableReference[@BlueprintName="WindowManagerTests"])' \
    "$scheme_file")
app_test_macro_expansions=$(/usr/bin/xmllint --xpath \
    'count(//TestAction/MacroExpansion/BuildableReference[@BlueprintName="WindowManager"])' \
    "$scheme_file")
test_macro_expansions=$(/usr/bin/xmllint --xpath \
    'count(//TestAction/MacroExpansion/BuildableReference[@BlueprintName="WindowManagerTests"])' \
    "$scheme_file")
app_run_entries=$(/usr/bin/xmllint --xpath \
    'count(//BuildActionEntry[@buildForRunning="YES"]/BuildableReference[@BlueprintName="WindowManager"])' \
    "$scheme_file")
app_archive_entries=$(/usr/bin/xmllint --xpath \
    'count(//BuildActionEntry[@buildForArchiving="YES"]/BuildableReference[@BlueprintName="WindowManager"])' \
    "$scheme_file")

[[ "$app_test_entries" == "0" ]] || { print -u2 "WindowManager app is enabled for testing"; exit 1; }
[[ "$test_bundle_entries" == "1" ]] || { print -u2 "WindowManagerTests is not the sole test build entry"; exit 1; }
[[ "$app_test_macro_expansions" == "0" ]] || { print -u2 "Test action still expands app macros"; exit 1; }
[[ "$test_macro_expansions" == "1" ]] || { print -u2 "Test action does not expand test-bundle macros"; exit 1; }
[[ "$app_run_entries" == "1" ]] || { print -u2 "WindowManager app is not enabled for Run"; exit 1; }
[[ "$app_archive_entries" == "1" ]] || { print -u2 "WindowManager app is not enabled for Archive"; exit 1; }

test_settings=$(/usr/bin/xcodebuild \
    -project "$project_file" \
    -target WindowManagerTests \
    -configuration Debug \
    -showBuildSettings)
test_host=$(print -r -- "$test_settings" | /usr/bin/awk -F ' = ' '/^[[:space:]]*TEST_HOST =/ && length($2) > 0 { print $2; exit }')
bundle_loader=$(print -r -- "$test_settings" | /usr/bin/awk -F ' = ' '/^[[:space:]]*BUNDLE_LOADER =/ && length($2) > 0 { print $2; exit }')

# Xcode may omit an explicitly empty setting from -showBuildSettings. Either omission or an
# empty value is valid; only a resolved host/loader would turn these into hosted tests.
[[ -z "$test_host" ]] || { print -u2 "TEST_HOST must be absent or empty"; exit 1; }
[[ -z "$bundle_loader" ]] || { print -u2 "BUNDLE_LOADER must be absent or empty"; exit 1; }

print "Test isolation verified: non-hosted tests do not build or macro-expand WindowManager.app."
