#!/bin/zsh

set -euo pipefail

script_name="${0:t}"
dmg_path=""

usage() {
    print "Usage: $script_name --dmg PATH"
    print ""
    print "Mounts a DMG read-only and verifies its app, Applications link, and Finder layout metadata."
}

while (( $# > 0 )); do
    case "$1" in
        --dmg)
            (( $# >= 2 )) || { print -u2 "--dmg requires a value"; exit 2; }
            dmg_path="$2"
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

[[ -n "$dmg_path" ]] || { print -u2 "Missing --dmg"; exit 2; }
dmg_path="${dmg_path:A}"
[[ -f "$dmg_path" ]] || { print -u2 "DMG not found: $dmg_path"; exit 1; }

mount_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/windowranger-dmg.XXXXXX")"
mounted=false

cleanup() {
    if [[ "$mounted" == true ]]; then
        /usr/bin/hdiutil detach "$mount_root" >/dev/null
    fi
    /bin/rmdir "$mount_root" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

/usr/bin/hdiutil verify "$dmg_path" >/dev/null
/usr/bin/hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "$mount_root" \
    "$dmg_path" >/dev/null
mounted=true

app="$mount_root/WindowRanger.app"
applications_link="$mount_root/Applications"

[[ -d "$app" ]] || { print -u2 "WindowRanger.app is missing from the DMG"; exit 1; }
[[ -L "$applications_link" ]] || { print -u2 "Applications is not a symbolic link"; exit 1; }
[[ "$(/usr/bin/readlink "$applications_link")" == "/Applications" ]] || {
    print -u2 "Applications link does not target /Applications"
    exit 1
}
[[ -f "$mount_root/.DS_Store" ]] || { print -u2 "Finder layout metadata is missing"; exit 1; }

background_png="$mount_root/.background.png"
background_tiff="$mount_root/.background.tiff"
if [[ -f "$background_tiff" ]]; then
    background_info="$(/usr/bin/tiffutil -info "$background_tiff")"
    [[ "$background_info" == *"Image Width: 720 Image Length: 450"* ]] || {
        print -u2 "DMG background is missing its 720x450 standard representation"
        exit 1
    }
    [[ "$background_info" == *"Image Width: 1440 Image Length: 900"* ]] || {
        print -u2 "DMG background is missing its 1440x900 Retina representation"
        exit 1
    }
elif [[ ! -f "$background_png" ]]; then
    print -u2 "DMG background image is missing"
    exit 1
fi

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
[[ "$bundle_identifier" == "dev.appranger.WindowRanger" ]] || {
    print -u2 "Unexpected bundle identifier in DMG: $bundle_identifier"
    exit 1
}

print "DMG verification passed: $dmg_path"
