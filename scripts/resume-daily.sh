#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
daily_app="${WINDOWRANGER_DAILY_APP:-/Applications/WindowRanger Dev.app}"
mode="${1:-interactive}"

case "$mode" in
    interactive|--scheme-action|--check) ;;
    -h|--help)
        print "Usage: ${0:t} [--check | --scheme-action]"
        print ""
        print "Launches the explicit daily app at: $daily_app"
        exit 0
        ;;
    *)
        print -u2 "Unknown option: $mode"
        exit 2
        ;;
esac

if [[ "$mode" == "--check" ]]; then
    if [[ -d "$daily_app" ]]; then
        print "Daily WindowRanger is installed at: $daily_app"
    else
        print "No daily WindowRanger is installed at: $daily_app"
    fi
    exit 0
fi

if [[ ! -d "$daily_app" ]]; then
    if [[ "$mode" == "interactive" ]]; then
        print "No daily WindowRanger is installed yet."
        print "When ready, run: $repository_root/scripts/install-daily.sh"
    fi
    exit 0
fi

"$repository_root/scripts/start-development.sh" --scheme-action
/usr/bin/open -g "$daily_app"
print "Daily WindowRanger resumed from: $daily_app"
