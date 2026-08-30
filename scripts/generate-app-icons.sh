#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source_dir="$repo_root/Brand/WindowRanger/icons/production/source"
export_dir="$repo_root/Brand/WindowRanger/icons/exports/macos"
asset_dir="$repo_root/Sources/Resources/Assets.xcassets/AppIcon.appiconset"

default_master="$source_dir/default-1024.png"
dark_master="$source_dir/dark-1024.png"
mono_master="$source_dir/mono-1024.png"

for required_master in "$default_master" "$dark_master" "$mono_master"; do
    if [[ ! -s "$required_master" ]]; then
        echo "Missing icon master: $required_master" >&2
        exit 1
    fi
done

mkdir -p \
    "$export_dir/default.iconset" \
    "$export_dir/dark.iconset" \
    "$export_dir/mono.iconset" \
    "$asset_dir"

resize_icon() {
    local source_path="$1"
    local pixels="$2"
    local output_path="$3"

    /usr/bin/sips -z "$pixels" "$pixels" "$source_path" --out "$output_path" >/dev/null
}

write_iconset() {
    local source_path="$1"
    local output_dir="$2"

    resize_icon "$source_path" 16 "$output_dir/icon_16x16.png"
    resize_icon "$source_path" 32 "$output_dir/icon_16x16@2x.png"
    resize_icon "$source_path" 32 "$output_dir/icon_32x32.png"
    resize_icon "$source_path" 64 "$output_dir/icon_32x32@2x.png"
    resize_icon "$source_path" 128 "$output_dir/icon_128x128.png"
    resize_icon "$source_path" 256 "$output_dir/icon_128x128@2x.png"
    resize_icon "$source_path" 256 "$output_dir/icon_256x256.png"
    resize_icon "$source_path" 512 "$output_dir/icon_256x256@2x.png"
    resize_icon "$source_path" 512 "$output_dir/icon_512x512.png"
    resize_icon "$source_path" 1024 "$output_dir/icon_512x512@2x.png"
}

write_iconset "$default_master" "$export_dir/default.iconset"
write_iconset "$dark_master" "$export_dir/dark.iconset"
write_iconset "$mono_master" "$export_dir/mono.iconset"

/usr/bin/iconutil -c icns "$export_dir/default.iconset" -o "$export_dir/WindowRanger.icns"
/usr/bin/iconutil -c icns "$export_dir/dark.iconset" -o "$export_dir/WindowRanger-dark.icns"
/usr/bin/iconutil -c icns "$export_dir/mono.iconset" -o "$export_dir/WindowRanger-mono.icns"

resize_icon "$default_master" 16 "$asset_dir/app-icon-16.png"
resize_icon "$default_master" 32 "$asset_dir/app-icon-16@2x.png"
resize_icon "$default_master" 32 "$asset_dir/app-icon-32.png"
resize_icon "$default_master" 64 "$asset_dir/app-icon-32@2x.png"
resize_icon "$default_master" 128 "$asset_dir/app-icon-128.png"
resize_icon "$default_master" 256 "$asset_dir/app-icon-128@2x.png"
resize_icon "$default_master" 256 "$asset_dir/app-icon-256.png"
resize_icon "$default_master" 512 "$asset_dir/app-icon-256@2x.png"
resize_icon "$default_master" 512 "$asset_dir/app-icon-512.png"
resize_icon "$default_master" 1024 "$asset_dir/app-icon-512@2x.png"

echo "Generated WindowRanger macOS app icons."
