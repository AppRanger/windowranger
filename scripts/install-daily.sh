#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
script_name="${0:t}"
project_file="$repository_root/WindowRanger.xcodeproj"
configuration="${WINDOWRANGER_DAILY_CONFIGURATION:-Debug}"
daily_app="${WINDOWRANGER_DAILY_APP:-/Applications/WindowRanger.app}"
derived_data_directory="${WINDOWRANGER_DAILY_DERIVED_DATA:-$repository_root/.build/DailyDerivedData}"
launch_after_install=true
source_revision="$(/usr/bin/git -C "$repository_root" rev-parse --short=12 HEAD)"
if [[ -n "$(/usr/bin/git -C "$repository_root" status --porcelain --untracked-files=normal)" ]]; then
    source_revision="$source_revision-dirty"
fi

usage() {
    print "Usage: $script_name [--debug | --release] [--no-launch]"
    print ""
    print "Builds, verifies, and installs the daily WindowRanger app."
    print "The default is Debug until you are ready to use Release."
    print ""
    print "Environment overrides:"
    print "  WINDOWRANGER_DAILY_APP"
    print "  WINDOWRANGER_DAILY_CONFIGURATION"
    print "  WINDOWRANGER_DAILY_DERIVED_DATA"
}

while (( $# > 0 )); do
    case "$1" in
        --debug) configuration="Debug" ;;
        --release) configuration="Release" ;;
        --no-launch) launch_after_install=false ;;
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

[[ "$configuration" == "Debug" || "$configuration" == "Release" ]] || {
    print -u2 "Configuration must be Debug or Release, not: $configuration"
    exit 2
}
[[ "$daily_app" == /* && "$daily_app" == *.app && "$daily_app" != "/" ]] || {
    print -u2 "WINDOWRANGER_DAILY_APP must be an absolute .app path."
    exit 2
}
[[ -d "$project_file" ]] || {
    print -u2 "Missing generated Xcode project: $project_file"
    exit 1
}

print "Building the $configuration daily app while the current copy remains available..."
/usr/bin/xcodebuild \
    -project "$project_file" \
    -scheme WindowRanger \
    -configuration "$configuration" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data_directory" \
    WINDOWRANGER_GIT_COMMIT="$source_revision" \
    build

built_app="$derived_data_directory/Build/Products/$configuration/WindowRanger.app"
[[ -d "$built_app" ]] || {
    print -u2 "Built app was not found at: $built_app"
    exit 1
}

/usr/bin/codesign --verify --deep --strict "$built_app"
built_bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$built_app/Contents/Info.plist")
[[ "$built_bundle_identifier" == "dev.appranger.WindowRanger" ]] || {
    print -u2 "Unexpected bundle identifier: $built_bundle_identifier"
    exit 1
}

destination_parent="${daily_app:h}"
/bin/mkdir -p "$destination_parent"
staging_directory=$(/usr/bin/mktemp -d "$destination_parent/.windowranger-install.XXXXXX")
staged_app="$staging_directory/WindowRanger"
backup_app="$destination_parent/.WindowRanger.previous"
original_moved=false

cleanup() {
    if [[ "$original_moved" == true && ! -e "$daily_app" && -e "$backup_app" ]]; then
        /bin/mv "$backup_app" "$daily_app"
    fi
    [[ ! -e "$staging_directory" ]] || /bin/rm -rf "$staging_directory"
}
trap cleanup EXIT INT TERM

/usr/bin/ditto "$built_app" "$staged_app"
"$repository_root/scripts/start-development.sh" --scheme-action

if [[ -e "$daily_app" ]]; then
    [[ ! -e "$backup_app" ]] || /bin/rm -rf "$backup_app"
    /bin/mv "$daily_app" "$backup_app"
    original_moved=true
fi

/bin/mv "$staged_app" "$daily_app"
/usr/bin/codesign --verify --deep --strict "$daily_app"

print "Installed $configuration WindowRanger at: $daily_app"
if [[ "$original_moved" == true ]]; then
    print "Previous daily build retained without an .app suffix at: $backup_app"
fi

if [[ "$launch_after_install" == true ]]; then
    "$repository_root/scripts/resume-daily.sh" --scheme-action
fi
