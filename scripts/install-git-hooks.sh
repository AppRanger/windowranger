#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
script_name="${0:t}"
action="${1:---install}"

usage() {
    print "Usage: $script_name [--install|--remove]"
    print ""
    print "Installs or removes WindowRanger's repository-managed Git hooks for this clone."
}

case "$action" in
    --install)
        ;;
    --remove)
        existing="$(git -C "$repository_root" config --local --get core.hooksPath || true)"
        if [[ "$existing" == ".githooks" ]]; then
            git -C "$repository_root" config --local --unset core.hooksPath
            print "WindowRanger Git hooks removed for this clone."
        elif [[ -n "$existing" ]]; then
            print -u2 "Not removing a different configured hooks path: $existing"
            exit 1
        else
            print "WindowRanger Git hooks are not installed for this clone."
        fi
        exit 0
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        print -u2 "Unknown option: $action"
        usage >&2
        exit 2
        ;;
esac

existing="$(git -C "$repository_root" config --local --get core.hooksPath || true)"
if [[ -n "$existing" && "$existing" != ".githooks" ]]; then
    print -u2 "This clone already uses a different Git hooks path: $existing"
    print -u2 "Review and combine that setup manually; it was not overwritten."
    exit 1
fi

git -C "$repository_root" config --local core.hooksPath .githooks
print "WindowRanger pre-push verification installed for this clone."
print "Remove it with: ./scripts/install-git-hooks.sh --remove"
