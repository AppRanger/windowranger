#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
script_name="${0:t}"
settings="$repository_root/config/dmg-settings.py"
tool_root="${WINDOWRANGER_DMG_TOOL_ROOT:-$repository_root/.build/dmg-tools}"
dmgbuild="${WINDOWRANGER_DMGBUILD:-$tool_root/bin/dmgbuild}"
volume_icon="$repository_root/Brand/WindowRanger/icons/exports/macos/WindowRanger.icns"
app_path=""
channel=""
output_path=""

usage() {
    print "Usage: $script_name --app PATH --channel stable|beta --output PATH"
    print ""
    print "Creates a styled DMG around an existing WindowRanger.app without signing or notarizing it."
}

while (( $# > 0 )); do
    case "$1" in
        --app)
            (( $# >= 2 )) || { print -u2 "--app requires a value"; exit 2; }
            app_path="$2"
            shift
            ;;
        --channel)
            (( $# >= 2 )) || { print -u2 "--channel requires a value"; exit 2; }
            channel="$2"
            shift
            ;;
        --output)
            (( $# >= 2 )) || { print -u2 "--output requires a value"; exit 2; }
            output_path="$2"
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

[[ -n "$app_path" ]] || { print -u2 "Missing --app"; exit 2; }
[[ -n "$channel" ]] || { print -u2 "Missing --channel"; exit 2; }
[[ -n "$output_path" ]] || { print -u2 "Missing --output"; exit 2; }
[[ "$channel" == "stable" || "$channel" == "beta" ]] || {
    print -u2 "Channel must be stable or beta: $channel"
    exit 2
}

app_path="${app_path:A}"
output_path="${output_path:A}"
background="$repository_root/Brand/WindowRanger/dmg/backgrounds/$channel-background.png"
volume_name="WindowRanger"
[[ "$channel" == "stable" ]] || volume_name="WindowRanger Beta"

[[ -d "$app_path" ]] || { print -u2 "Application bundle not found: $app_path"; exit 1; }
[[ -f "$settings" ]] || { print -u2 "DMG settings not found: $settings"; exit 1; }
[[ -f "$background" ]] || { print -u2 "DMG background not found: $background"; exit 1; }
[[ -f "$volume_icon" ]] || { print -u2 "DMG volume icon not found: $volume_icon"; exit 1; }
[[ -x "$dmgbuild" ]] || {
    print -u2 "dmgbuild is not installed at $dmgbuild"
    print -u2 "Run ./scripts/install-dmg-tools.sh first."
    exit 1
}
[[ ! -e "$output_path" ]] || { print -u2 "DMG output already exists: $output_path"; exit 1; }

/bin/mkdir -p "${output_path:h}"
"$dmgbuild" \
    -s "$settings" \
    -D "app=$app_path" \
    -D "background=$background" \
    -D "volume_icon=$volume_icon" \
    "$volume_name" \
    "$output_path"

/usr/bin/hdiutil verify "$output_path"
print "DMG ready: $output_path"
