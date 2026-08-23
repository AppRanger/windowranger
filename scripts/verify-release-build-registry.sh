#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
script_name="${0:t}"
registry="${WINDOWRANGER_RELEASE_BUILD_REGISTRY:-$repository_root/config/release-builds.tsv}"
version=""
build_number=""

usage() {
    print "Usage: $script_name [--version VERSION --build-number NUMBER]"
    print ""
    print "Validates the append-only public build-number ledger. When a version and build number are"
    print "supplied, also requires that exact pair to be the latest allocated entry."
}

while (( $# > 0 )); do
    case "$1" in
        --version)
            (( $# >= 2 )) || { print -u2 "--version requires a value"; exit 2; }
            version="$2"
            shift
            ;;
        --build-number)
            (( $# >= 2 )) || { print -u2 "--build-number requires a value"; exit 2; }
            build_number="$2"
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

if [[ -n "$version" || -n "$build_number" ]]; then
    [[ -n "$version" && -n "$build_number" ]] || {
        print -u2 "--version and --build-number must be supplied together"
        exit 2
    }
fi

[[ -f "$registry" ]] || { print -u2 "Release build registry not found: $registry"; exit 1; }

typeset -A seen_builds
typeset -A seen_allocations
previous_build=0
latest_build=0
line_number=0
matching_state=""
active_allocation_count=0

while IFS=$'\t' read -r row_build row_version row_state row_note extra; do
    (( line_number += 1 ))
    [[ -z "$row_build" || "$row_build" == \#* ]] && continue

    [[ -z "$extra" ]] || {
        print -u2 "$registry:$line_number has more than four tab-separated columns"
        exit 1
    }
    print -r -- "$row_build" | /usr/bin/grep -Eq '^[1-9][0-9]*$' || {
        print -u2 "$registry:$line_number has an invalid build number: $row_build"
        exit 1
    }
    print -r -- "$row_version" | /usr/bin/grep -Eq \
        '^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[1-9][0-9]*)?$' || {
        print -u2 "$registry:$line_number has an invalid version: $row_version"
        exit 1
    }
    [[ "$row_state" == allocated || "$row_state" == published || "$row_state" == superseded ]] || {
        print -u2 "$registry:$line_number has an invalid state: $row_state"
        exit 1
    }
    [[ -n "$row_note" ]] || {
        print -u2 "$registry:$line_number must record why build $row_build was allocated"
        exit 1
    }
    [[ -z "${seen_builds[$row_build]-}" ]] || {
        print -u2 "$registry:$line_number reuses build number $row_build"
        exit 1
    }
    (( row_build > previous_build )) || {
        print -u2 "$registry:$line_number is out of order; build numbers must only be appended"
        exit 1
    }

    allocation_key="$row_version:$row_build"
    [[ -z "${seen_allocations[$allocation_key]-}" ]] || {
        print -u2 "$registry:$line_number duplicates allocation $allocation_key"
        exit 1
    }
    seen_builds[$row_build]=1
    seen_allocations[$allocation_key]=1
    previous_build="$row_build"
    latest_build="$row_build"

    if [[ "$row_state" == allocated ]]; then
        (( active_allocation_count += 1 ))
    elif (( active_allocation_count > 0 )); then
        print -u2 "$registry:$line_number follows an active allocation; resolve it before appending another row"
        exit 1
    fi

    if [[ "$row_version" == "$version" && "$row_build" == "$build_number" ]]; then
        matching_state="$row_state"
    fi
done < "$registry"

(( latest_build > 0 )) || { print -u2 "Release build registry is empty: $registry"; exit 1; }
(( active_allocation_count <= 1 )) || {
    print -u2 "Release build registry contains more than one active allocation"
    exit 1
}

if [[ -n "$version" ]]; then
    [[ "$matching_state" == allocated ]] || {
        if [[ -z "$matching_state" ]]; then
            print -u2 "Build $build_number for $version has not been allocated in $registry"
        else
            print -u2 "Build $build_number for $version is '$matching_state', not an active allocation"
        fi
        exit 1
    }
    [[ "$build_number" == "$latest_build" ]] || {
        print -u2 "Build $build_number is not the latest reserved number ($latest_build)"
        exit 1
    }
fi

print "Release build registry verified through build $latest_build."
