#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
source_root="$repository_root/Brand/WindowRanger/dmg/source"
output_root="$repository_root/Brand/WindowRanger/dmg/backgrounds"
renderer="$repository_root/scripts/render-dmg-background.swift"

/bin/mkdir -p "$output_root"

"$renderer" \
    --input "$source_root/stable-approved.png" \
    --output "$output_root/stable-background.png" \
    --channel stable
"$renderer" \
    --input "$source_root/beta-approved.png" \
    --output "$output_root/beta-background.png" \
    --channel beta

for background in "$output_root"/*-background.png; do
    dimensions="$(/usr/bin/sips -g pixelWidth -g pixelHeight "$background")"
    [[ "$dimensions" == *"pixelWidth: 720"* && "$dimensions" == *"pixelHeight: 450"* ]] || {
        print -u2 "Unexpected DMG background dimensions: $background"
        exit 1
    }

    retina_background="${background:r}@2x.${background:e}"
    retina_dimensions="$(/usr/bin/sips -g pixelWidth -g pixelHeight "$retina_background")"
    [[ "$retina_dimensions" == *"pixelWidth: 1440"* && "$retina_dimensions" == *"pixelHeight: 900"* ]] || {
        print -u2 "Unexpected Retina DMG background dimensions: $retina_background"
        exit 1
    }
done

print "Stable and Beta Retina DMG backgrounds are ready."
