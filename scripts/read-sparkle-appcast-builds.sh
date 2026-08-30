#!/bin/zsh

set -euo pipefail

script_name="${0:t}"
appcast="${1:-}"

[[ $# == 1 && -n "$appcast" ]] || {
    print -u2 "Usage: $script_name APPCAST"
    exit 2
}
[[ -f "$appcast" ]] || { print -u2 "Appcast not found: $appcast"; exit 1; }
[[ -x /usr/bin/xmllint ]] || { print -u2 "xmllint is required"; exit 1; }

/usr/bin/xmllint --nonet --noout "$appcast"

# Sparkle recommends a top-level <sparkle:version>, while older feeds may place the same value on
# the enclosure. Accept both representations but keep WindowRanger's public build contract numeric.
version_nodes="//*[local-name()='item']/*[local-name()='version']/text() | //*[local-name()='item']/*[local-name()='enclosure']/@*[local-name()='version']"
version_count="$(/usr/bin/xmllint --nonet --xpath "count($version_nodes)" "$appcast")"
print -r -- "$version_count" | /usr/bin/grep -Eq '^[1-9][0-9]*$' || {
    print -u2 "Appcast contains no Sparkle build versions: $appcast"
    exit 1
}

for (( index = 1; index <= version_count; index += 1 )); do
    build="$(/usr/bin/xmllint --nonet --xpath \
        "normalize-space(string(($version_nodes)[$index]))" "$appcast")"
    print -r -- "$build" | /usr/bin/grep -Eq '^[1-9][0-9]*$' || {
        print -u2 "Appcast contains a non-numeric Sparkle build version: $build"
        exit 1
    }
    print -r -- "$build"
done | /usr/bin/sort -nu
